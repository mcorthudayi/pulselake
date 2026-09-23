using System.Diagnostics;
using System.Security.Claims;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Mvc;
using Npgsql;
using NpgsqlTypes;

var builder = WebApplication.CreateBuilder(args);

var connectionString = builder.Configuration.GetConnectionString("PulseLake")
    ?? throw new InvalidOperationException("ConnectionStrings:PulseLake is not configured. Start the API with scripts/api.sh.");

builder.Services.AddSingleton(NpgsqlDataSource.Create(connectionString));
builder.Services.AddProblemDetails();
builder.Services.AddAuthentication().AddJwtBearer();
builder.Services.AddAuthorizationBuilder()
    .AddPolicy("Clinician", policy => policy.RequireRole("clinician"))
    .AddPolicy("Analyst", policy => policy.RequireRole("analyst"))
    .AddPolicy("Auditor", policy => policy.RequireRole("auditor"));
builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.GlobalLimiter = PartitionedRateLimiter.Create<HttpContext, string>(context =>
        RateLimitPartition.GetFixedWindowLimiter(
            context.User.FindFirstValue(ClaimTypes.NameIdentifier)
                ?? context.Connection.RemoteIpAddress?.ToString()
                ?? "anonymous",
            _ => new FixedWindowRateLimiterOptions
            {
                PermitLimit = 120,
                Window = TimeSpan.FromMinutes(1)
            }));
});

var app = builder.Build();

app.UseExceptionHandler();
app.Use(async (context, next) =>
{
    context.Response.Headers.XContentTypeOptions = "nosniff";
    context.Response.Headers.XFrameOptions = "DENY";
    context.Response.Headers.CacheControl = "no-store";
    await next();
});
app.UseAuthentication();
app.UseMiddleware<AuditMiddleware>();
app.UseRateLimiter();
app.UseAuthorization();

app.MapGet("/health", () => Results.Ok(new { status = "ok" }));

app.MapGet("/fhir/metadata", () => Results.Text(Fhir.CapabilityStatement, Fhir.ContentType));

var fhir = app.MapGroup("/fhir").RequireAuthorization("Clinician");

fhir.MapGet("/{type}/{id}", async (string type, string id, NpgsqlDataSource db, CancellationToken ct) =>
{
    if (!Fhir.SupportedTypes.Contains(type))
        return Fhir.Outcome(StatusCodes.Status404NotFound, "not-supported", "Resource type is not supported.");
    if (!Fhir.IdPattern.IsMatch(id))
        return Fhir.Outcome(StatusCodes.Status400BadRequest, "invalid", "Invalid resource id.");

    await using var command = db.CreateCommand("""
        SELECT resource::text
        FROM raw.fhir_resources
        WHERE resource_type = @type AND resource_id = @id
        """);
    command.Parameters.Add(Db.Param("type", NpgsqlDbType.Text, type));
    command.Parameters.Add(Db.Param("id", NpgsqlDbType.Text, id));

    return await command.ExecuteScalarAsync(ct) is string json
        ? Results.Text(json, Fhir.ContentType)
        : Fhir.Outcome(StatusCodes.Status404NotFound, "not-found", "Resource not found.");
});

fhir.MapGet("/{type}", async (
    string type,
    string? name,
    string? gender,
    string? birthdate,
    string? patient,
    [FromQuery(Name = "_count")] int? count,
    NpgsqlDataSource db,
    CancellationToken ct) =>
{
    if (!Fhir.SupportedTypes.Contains(type))
        return Fhir.Outcome(StatusCodes.Status404NotFound, "not-supported", "Resource type is not supported.");

    var limit = Math.Clamp(count ?? 20, 1, 100);
    await using var command = db.CreateCommand();

    if (type == "Patient")
    {
        if (name is { Length: > 64 })
            return Fhir.Outcome(StatusCodes.Status400BadRequest, "invalid", "Parameter 'name' is too long.");
        if (gender is not null && gender is not ("male" or "female" or "other" or "unknown"))
            return Fhir.Outcome(StatusCodes.Status400BadRequest, "invalid", "Parameter 'gender' must be male, female, other or unknown.");

        DateOnly? birth = null;
        if (birthdate is not null)
        {
            if (!DateOnly.TryParseExact(birthdate, "yyyy-MM-dd", out var parsed))
                return Fhir.Outcome(StatusCodes.Status400BadRequest, "invalid", "Parameter 'birthdate' must be yyyy-MM-dd.");
            birth = parsed;
        }

        command.CommandText = Fhir.PatientSearchSql;
        command.Parameters.Add(Db.Param("name", NpgsqlDbType.Text, name is null ? null : Fhir.EscapeLike(name)));
        command.Parameters.Add(Db.Param("gender", NpgsqlDbType.Text, gender));
        command.Parameters.Add(Db.Param("birthdate", NpgsqlDbType.Date, birth));
    }
    else
    {
        if (patient is null || !Fhir.IdPattern.IsMatch(patient))
            return Fhir.Outcome(StatusCodes.Status400BadRequest, "required", "Search requires a valid 'patient' parameter.");

        command.CommandText = Fhir.ByPatientSearchSql;
        command.Parameters.Add(Db.Param("type", NpgsqlDbType.Text, type));
        command.Parameters.Add(Db.Param("field", NpgsqlDbType.Text, Fhir.PatientField(type)));
        command.Parameters.Add(Db.Param("patient", NpgsqlDbType.Text, patient));
    }

    command.Parameters.Add(Db.Param("limit", NpgsqlDbType.Integer, limit));

    var resources = new List<string>();
    await using var reader = await command.ExecuteReaderAsync(ct);
    while (await reader.ReadAsync(ct))
        resources.Add(reader.GetString(0));

    return Fhir.Bundle(resources);
});

var deid = app.MapGroup("/deid").RequireAuthorization("Analyst");

deid.MapGet("/patients", async (string? ageBand, string? gender, int? limit, NpgsqlDataSource db, CancellationToken ct) =>
{
    await using var command = db.CreateCommand("""
        SELECT patient_key, gender, birth_year, age_band, is_deceased, state, zip3
        FROM deid.deid_patients
        WHERE (@age_band IS NULL OR age_band = @age_band)
          AND (@gender IS NULL OR gender = @gender)
        ORDER BY patient_key
        LIMIT @limit
        """);
    command.Parameters.Add(Db.Param("age_band", NpgsqlDbType.Text, ageBand));
    command.Parameters.Add(Db.Param("gender", NpgsqlDbType.Text, gender));
    command.Parameters.Add(Db.Param("limit", NpgsqlDbType.Integer, Math.Clamp(limit ?? 50, 1, 500)));

    var rows = new List<DeidPatient>();
    await using var reader = await command.ExecuteReaderAsync(ct);
    while (await reader.ReadAsync(ct))
    {
        rows.Add(new DeidPatient(
            reader.GetString(0),
            reader.IsDBNull(1) ? null : reader.GetString(1),
            reader.IsDBNull(2) ? null : reader.GetInt32(2),
            reader.GetString(3),
            reader.GetBoolean(4),
            reader.IsDBNull(5) ? null : reader.GetString(5),
            reader.IsDBNull(6) ? null : reader.GetString(6)));
    }

    return Results.Ok(rows);
});

deid.MapGet("/stats/top-conditions", async (int? limit, NpgsqlDataSource db, CancellationToken ct) =>
{
    await using var command = db.CreateCommand("""
        SELECT condition_name,
               count(DISTINCT patient_key)::int AS patients,
               count(*)::int AS occurrences
        FROM deid.deid_conditions
        GROUP BY condition_name
        HAVING count(DISTINCT patient_key) >= @min_cell
        ORDER BY patients DESC, condition_name
        LIMIT @limit
        """);
    command.Parameters.Add(Db.Param("min_cell", NpgsqlDbType.Integer, Privacy.MinCellSize));
    command.Parameters.Add(Db.Param("limit", NpgsqlDbType.Integer, Math.Clamp(limit ?? 10, 1, 100)));

    var rows = new List<ConditionStat>();
    await using var reader = await command.ExecuteReaderAsync(ct);
    while (await reader.ReadAsync(ct))
        rows.Add(new ConditionStat(reader.IsDBNull(0) ? null : reader.GetString(0), reader.GetInt32(1), reader.GetInt32(2)));

    return Results.Ok(new { minCellSize = Privacy.MinCellSize, conditions = rows });
});

app.MapGet("/audit/access-log", async (string? user, int? limit, NpgsqlDataSource db, CancellationToken ct) =>
{
    await using var command = db.CreateCommand("""
        SELECT id, occurred_at, user_name, roles, method, path, query_string,
               resource_type, resource_id, status_code, duration_ms
        FROM audit.access_log
        WHERE (@user IS NULL OR user_name = @user)
        ORDER BY id DESC
        LIMIT @limit
        """);
    command.Parameters.Add(Db.Param("user", NpgsqlDbType.Text, user));
    command.Parameters.Add(Db.Param("limit", NpgsqlDbType.Integer, Math.Clamp(limit ?? 50, 1, 500)));

    var rows = new List<AuditEntry>();
    await using var reader = await command.ExecuteReaderAsync(ct);
    while (await reader.ReadAsync(ct))
    {
        rows.Add(new AuditEntry(
            reader.GetInt64(0),
            reader.GetDateTime(1),
            reader.IsDBNull(2) ? null : reader.GetString(2),
            reader.IsDBNull(3) ? null : reader.GetString(3),
            reader.GetString(4),
            reader.GetString(5),
            reader.IsDBNull(6) ? null : reader.GetString(6),
            reader.IsDBNull(7) ? null : reader.GetString(7),
            reader.IsDBNull(8) ? null : reader.GetString(8),
            reader.GetInt32(9),
            reader.GetInt32(10)));
    }

    return Results.Ok(rows);
}).RequireAuthorization("Auditor");

app.Run();

record DeidPatient(string PatientKey, string? Gender, int? BirthYear, string AgeBand, bool IsDeceased, string? State, string? Zip3);

record ConditionStat(string? ConditionName, int Patients, int Occurrences);

record AuditEntry(
    long Id,
    DateTime OccurredAt,
    string? UserName,
    string? Roles,
    string Method,
    string Path,
    string? QueryString,
    string? ResourceType,
    string? ResourceId,
    int StatusCode,
    int DurationMs);

static class Privacy
{
    public const int MinCellSize = 5;
}

static class Db
{
    public static NpgsqlParameter Param(string name, NpgsqlDbType type, object? value) =>
        new(name, type) { Value = value ?? DBNull.Value };
}

static class Fhir
{
    public const string ContentType = "application/fhir+json";

    public static readonly HashSet<string> SupportedTypes = new(StringComparer.Ordinal)
    {
        "Patient", "Encounter", "Condition", "Observation", "Procedure",
        "MedicationRequest", "Immunization", "AllergyIntolerance", "DiagnosticReport", "CarePlan"
    };

    public static readonly Regex IdPattern = new(@"^[A-Za-z0-9\-\.]{1,64}$", RegexOptions.Compiled);

    public static readonly string CapabilityStatement = BuildCapabilityStatement();

    public const string PatientSearchSql = """
        SELECT resource::text
        FROM raw.fhir_resources
        WHERE resource_type = 'Patient'
          AND (@name IS NULL OR EXISTS (
                SELECT 1
                FROM jsonb_array_elements(resource->'name') AS n
                WHERE n->>'family' ILIKE @name || '%'
                   OR EXISTS (
                        SELECT 1
                        FROM jsonb_array_elements_text(n->'given') AS g
                        WHERE g ILIKE @name || '%')))
          AND (@gender IS NULL OR resource->>'gender' = @gender)
          AND (@birthdate IS NULL OR (resource->>'birthDate')::date = @birthdate)
        ORDER BY resource_id
        LIMIT @limit
        """;

    public const string ByPatientSearchSql = """
        SELECT resource::text
        FROM raw.fhir_resources
        WHERE resource_type = @type
          AND (resource @> jsonb_build_object(@field, jsonb_build_object('reference', 'urn:uuid:' || @patient))
            OR resource @> jsonb_build_object(@field, jsonb_build_object('reference', 'Patient/' || @patient)))
        ORDER BY resource_id
        LIMIT @limit
        """;

    public static string PatientField(string type) =>
        type is "Immunization" or "AllergyIntolerance" ? "patient" : "subject";

    public static string EscapeLike(string value) =>
        value.Replace("\\", "\\\\").Replace("%", "\\%").Replace("_", "\\_");

    public static IResult Outcome(int statusCode, string code, string diagnostics)
    {
        var outcome = new JsonObject
        {
            ["resourceType"] = "OperationOutcome",
            ["issue"] = new JsonArray(new JsonObject
            {
                ["severity"] = "error",
                ["code"] = code,
                ["diagnostics"] = diagnostics
            })
        };
        return Results.Text(outcome.ToJsonString(), ContentType, statusCode: statusCode);
    }

    public static IResult Bundle(IReadOnlyList<string> resources)
    {
        var entries = new JsonArray();
        foreach (var json in resources)
        {
            var resource = JsonNode.Parse(json)!;
            var fullUrl = $"{resource["resourceType"]?.GetValue<string>()}/{resource["id"]?.GetValue<string>()}";
            entries.Add(new JsonObject { ["fullUrl"] = fullUrl, ["resource"] = resource });
        }

        var bundle = new JsonObject
        {
            ["resourceType"] = "Bundle",
            ["type"] = "searchset",
            ["entry"] = entries
        };
        return Results.Text(bundle.ToJsonString(), ContentType);
    }

    private static string BuildCapabilityStatement()
    {
        var resources = new JsonArray();
        foreach (var type in SupportedTypes.Order())
        {
            var searchParams = type == "Patient"
                ? new JsonArray(SearchParam("name", "string"), SearchParam("gender", "token"), SearchParam("birthdate", "date"))
                : new JsonArray(SearchParam("patient", "reference"));

            resources.Add(new JsonObject
            {
                ["type"] = type,
                ["interaction"] = new JsonArray(new JsonObject { ["code"] = "read" }, new JsonObject { ["code"] = "search-type" }),
                ["searchParam"] = searchParams
            });
        }

        var statement = new JsonObject
        {
            ["resourceType"] = "CapabilityStatement",
            ["status"] = "active",
            ["kind"] = "instance",
            ["fhirVersion"] = "4.0.1",
            ["format"] = new JsonArray("application/fhir+json"),
            ["rest"] = new JsonArray(new JsonObject
            {
                ["mode"] = "server",
                ["security"] = new JsonObject { ["description"] = "JWT bearer token with role 'clinician' required." },
                ["resource"] = resources
            })
        };
        return statement.ToJsonString();
    }

    private static JsonObject SearchParam(string name, string type) =>
        new() { ["name"] = name, ["type"] = type };
}

sealed class AuditMiddleware(RequestDelegate next, NpgsqlDataSource dataSource, ILogger<AuditMiddleware> logger)
{
    private static readonly string[] AuditedPrefixes = ["/fhir", "/deid", "/audit"];

    public async Task InvokeAsync(HttpContext context)
    {
        var path = context.Request.Path.Value ?? string.Empty;
        var audited = AuditedPrefixes.Any(prefix => path.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            && !path.Equals("/fhir/metadata", StringComparison.OrdinalIgnoreCase);

        if (!audited)
        {
            await next(context);
            return;
        }

        var stopwatch = Stopwatch.StartNew();
        var statusCode = StatusCodes.Status500InternalServerError;
        try
        {
            await next(context);
            statusCode = context.Response.StatusCode;
        }
        finally
        {
            stopwatch.Stop();
            await WriteEntryAsync(context, path, statusCode, (int)stopwatch.ElapsedMilliseconds);
        }
    }

    private async Task WriteEntryAsync(HttpContext context, string path, int statusCode, int durationMs)
    {
        try
        {
            var user = context.User;
            var authenticated = user.Identity?.IsAuthenticated == true;
            var userName = authenticated ? user.Identity!.Name ?? user.FindFirstValue(ClaimTypes.NameIdentifier) : null;
            var roles = authenticated ? string.Join(",", user.FindAll(ClaimTypes.Role).Select(claim => claim.Value)) : null;

            await using var command = dataSource.CreateCommand("""
                INSERT INTO audit.access_log
                    (user_name, roles, method, path, query_string, resource_type, resource_id, status_code, client_ip, duration_ms)
                VALUES
                    (@user_name, @roles, @method, @path, @query_string, @resource_type, @resource_id, @status_code, @client_ip, @duration_ms)
                """);
            command.Parameters.Add(Db.Param("user_name", NpgsqlDbType.Text, userName));
            command.Parameters.Add(Db.Param("roles", NpgsqlDbType.Text, roles));
            command.Parameters.Add(Db.Param("method", NpgsqlDbType.Text, context.Request.Method));
            command.Parameters.Add(Db.Param("path", NpgsqlDbType.Text, path));
            command.Parameters.Add(Db.Param("query_string", NpgsqlDbType.Text, context.Request.QueryString.HasValue ? context.Request.QueryString.Value : null));
            command.Parameters.Add(Db.Param("resource_type", NpgsqlDbType.Text, context.GetRouteValue("type")?.ToString()));
            command.Parameters.Add(Db.Param("resource_id", NpgsqlDbType.Text, context.GetRouteValue("id")?.ToString()));
            command.Parameters.Add(Db.Param("status_code", NpgsqlDbType.Integer, statusCode));
            command.Parameters.Add(Db.Param("client_ip", NpgsqlDbType.Text, context.Connection.RemoteIpAddress?.ToString()));
            command.Parameters.Add(Db.Param("duration_ms", NpgsqlDbType.Integer, durationMs));
            await command.ExecuteNonQueryAsync(CancellationToken.None);
        }
        catch (Exception exception)
        {
            logger.LogError(exception, "Failed to write audit entry for {Path}", path);
        }
    }
}
