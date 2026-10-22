BeforeAll {
  $script:repo = Split-Path $PSScriptRoot -Parent
  $script:fixture = Join-Path $TestDrive 'validation-worker-transport'
  $script:fixtureScripts = Join-Path $script:fixture 'scripts'
  $script:fixtureSrc = Join-Path $script:fixture 'src'
  New-Item -ItemType Directory -Path $script:fixtureScripts,$script:fixtureSrc -Force | Out-Null
  Copy-Item (Join-Path $script:repo 'scripts/FunctionValidation.Worker.ps1') $script:fixtureScripts
  Copy-Item (Join-Path $script:repo 'scripts/FunctionValidation.Session.psm1') $script:fixtureScripts
  Copy-Item (Join-Path $script:repo 'src/Maester.ValidationProtocol.psm1') $script:fixtureSrc
  Import-Module (Join-Path $script:repo 'src/Maester.ValidationProtocol.psm1') -Force
  if (-not ('AzdMaesterValidation.BoundedIO' -as [type])) {
    Add-Type -Path (Join-Path $script:repo 'scripts/FunctionValidation.Transport.cs')
  }
  $fakeTransport = @'
using System;
using System.Globalization;
using System.IO;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using System.Xml.Linq;

namespace AzdMaesterValidation {
  public sealed class HttpResult {
    public int StatusCode { get; set; }
    public byte[] Bytes { get; set; } = Array.Empty<byte>();
    public string ETag { get; set; }
  }
  public static class BoundedIO {
    private static string Env(string name, string fallback = "") => Environment.GetEnvironmentVariable(name) ?? fallback;
    private static string B64Url(byte[] bytes) => Convert.ToBase64String(bytes).TrimEnd('=').Replace('+','-').Replace('/','_');
    private static string Json(object value) => JsonSerializer.Serialize(value);
    private static void Trace(object value) {
      var path = Env("AZD_FAKE_TRACE_PATH");
      if (!String.IsNullOrEmpty(path)) File.AppendAllText(path, Json(value) + Environment.NewLine, new UTF8Encoding(false));
    }
    public static void ValidateJsonObject(string text) {
      using var doc = JsonDocument.Parse(text);
      if (doc.RootElement.ValueKind != JsonValueKind.Object) throw new InvalidDataException("Expected object.");
    }
    public static Task<string> Run(string executable, string script, string input, int seconds) {
      if (seconds < 1 || seconds > 30) throw new InvalidDataException("Bad synthetic CLI bound.");
      using var doc = JsonDocument.Parse(input);
      var resource = doc.RootElement.GetProperty("resource").GetString();
      var tenant = Env("AZD_FAKE_TENANT");
      var oid = Env("AZD_FAKE_OPERATOR");
      var aud = resource;
      var mode = Env("AZD_FAKE_TOKEN_MODE", Env("AZD_FAKE_MODE"));
      if (mode == "WrongTokenOid") oid = "99999999-9999-4999-8999-999999999999";
      if (mode == "WrongTokenAudience") aud = "https://foreign.invalid/";
      var claims = Json(new { tid = tenant, oid, aud });
      var token = "e30." + B64Url(Encoding.UTF8.GetBytes(claims)) + ".synthetic-secret-never-output";
      Trace(new { kind = "token-request", resource, synthetic = true });
      return Task.FromResult(Json(new { accessToken = token }));
    }
    private static Task<HttpResult> Reply(int status, string body = "{}", string etag = null) => Task.FromResult(new HttpResult { StatusCode = status, Bytes = Encoding.UTF8.GetBytes(body), ETag = etag });
    private static string ContextSha(string text) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text))).ToLowerInvariant();
    private static (string claim, string terminal) CreateEvidence(string contextJson) {
      using var doc = JsonDocument.Parse(contextJson);
      var id = doc.RootElement.GetProperty("validationId").GetString();
      var hash = ContextSha(contextJson);
      var now = DateTimeOffset.UtcNow;
      var invocation = "77777777-7777-4777-8777-777777777777";
      var started = now.ToString("o", CultureInfo.InvariantCulture);
      var claim = Json(new { schemaVersion = 2, validationId = id, invocationId = invocation, contextSha256 = hash, status = "Started", startedAt = started });
      var terminal = Json(new { schemaVersion = 2, validationId = id, invocationId = invocation, contextSha256 = hash, status = "Succeeded", startedAt = started, completedAt = now.AddSeconds(1).ToString("o", CultureInfo.InvariantCulture) });
      return (claim, terminal);
    }
    public static Task<HttpResult> Send(string method, Uri uri, string token, string body, int seconds, bool xmlBody) {
      if (seconds < 1 || seconds > 30 || uri.Scheme != "https" || uri.Port != 443) throw new InvalidDataException("Invalid synthetic request bound.");
      var mode = Env("AZD_FAKE_MODE");
      var status = 200;
      var response = "{}";
      string etag = null;
      var path = uri.AbsolutePath;
      Trace(new { kind = "request-attempt", method, host = uri.Host, path, queryPresent = !String.IsNullOrEmpty(uri.Query) });
      if (uri.Host == "management.azure.com" && path.EndsWith("/subscriptions/" + Env("AZD_FAKE_SUB"), StringComparison.Ordinal)) {
        status = mode == "UnknownPreflight" ? 503 : 200;
        response = Json(new { id = "/subscriptions/" + Env("AZD_FAKE_SUB"), subscriptionId = Env("AZD_FAKE_SUB"), tenantId = Env("AZD_FAKE_TENANT"), state = "Enabled" });
      } else if (uri.Host == "management.azure.com" && path.EndsWith("/providers/Microsoft.Web/sites/" + Env("AZD_FAKE_SITE"), StringComparison.Ordinal)) {
        var principal = mode == "ArrayPrincipal" ? "[\"" + Env("AZD_FAKE_WORKLOAD") + "\"]" : JsonSerializer.Serialize(Env("AZD_FAKE_WORKLOAD"));
        var storageValue = mode == "WrongDeploymentStorage" ? "https://stother.blob.core.windows.net/deploymentpackage" : "https://" + Env("AZD_FAKE_STORAGE") + ".blob.core.windows.net/deploymentpackage";
        var authType = mode == "WrongDeploymentAuth" ? "StorageAccountConnectionString" : "SystemAssignedIdentity";
        response = "{\"id\":" + JsonSerializer.Serialize(path) + ",\"kind\":\"functionapp,linux\",\"identity\":{\"principalId\":" + principal + "},\"properties\":{\"state\":" + JsonSerializer.Serialize(Env("AZD_FAKE_SITE_STATE", "Running")) + ",\"functionAppConfig\":{\"deployment\":{\"storage\":{\"type\":\"blobContainer\",\"value\":" + JsonSerializer.Serialize(storageValue) + ",\"authentication\":{\"type\":" + JsonSerializer.Serialize(authType) + "}}}}}}";
      } else if (uri.Host == "management.azure.com" && path.EndsWith("/config/appsettings/list", StringComparison.Ordinal)) {
        status = 200;
        var account = mode == "WrongQueueAccount" ? "stother" : Env("AZD_FAKE_QUEUE");
        Trace(new { kind = "synthetic-settings-shape", queueAccountPresent = !String.IsNullOrEmpty(account), queueAccountLength = account.Length });
        response = Json(new { properties = new { AzureWebJobsStorage__accountName = account } });
      } else if (uri.Host == Env("AZD_FAKE_STORAGE") + ".blob.core.windows.net" && path == "/deploymentpackage/kudu-state.json" && method == "GET") {
        etag = Env("AZD_FAKE_SELECTOR_ETAG");
        var id = Env("AZD_FAKE_DEPLOYMENT");
        response = "{\"ActiveDeploymentId\":" + JsonSerializer.Serialize(id) + ",\"LatestDeploymentId\":" + JsonSerializer.Serialize(id) + ",\"Deployments\":{" + JsonSerializer.Serialize(id) + ":{\"Id\":" + JsonSerializer.Serialize(id) + ",\"Complete\":true,\"Status\":4,\"UploadedPackageName\":\"released-package.zip\"}}}";
      } else if (uri.Host == Env("AZD_FAKE_STORAGE") + ".blob.core.windows.net" && path == "/deploymentpackage/released-package.zip" && method == "HEAD") {
        etag = Env("AZD_FAKE_PACKAGE_ETAG"); response = "";
      } else if (uri.Host == Env("AZD_FAKE_STORAGE") + ".blob.core.windows.net" && path.StartsWith("/validation/", StringComparison.Ordinal)) {
        var reconcile = mode == "ReconcileStopped";
        var occupied = mode == "OccupiedClaim" && path.EndsWith(".claim.json", StringComparison.Ordinal);
        var claim = Env("AZD_FAKE_CLAIM_JSON");
        var terminal = Env("AZD_FAKE_TERMINAL_JSON");
        if (path.EndsWith(".claim.json", StringComparison.Ordinal) && !String.IsNullOrEmpty(claim)) { status = 200; response = claim; }
        else if (path.EndsWith(".json", StringComparison.Ordinal) && !String.IsNullOrEmpty(terminal)) { status = 200; response = terminal; }
        else if (occupied) { status = 200; response = "{}"; }
        else { status = 404; response = "{}"; }
      } else if (uri.Host == Env("AZD_FAKE_QUEUE") + ".queue.core.windows.net" && path == "/maester-validation/messages" && method == "POST") {
        Trace(new { kind = "queue-post", mode, method, path, status = mode == "Queue503" ? 503 : 201, authPresent = !String.IsNullOrEmpty(token), secretLeaked = false });
        if (mode == "Queue503") return Reply(503, "{}");
        var xml = XDocument.Parse(body);
        var messageText = Encoding.UTF8.GetString(Convert.FromBase64String(xml.Root.Element("MessageText").Value));
        var evidence = CreateEvidence(messageText);
        Environment.SetEnvironmentVariable("AZD_FAKE_CLAIM_JSON", evidence.claim);
        Environment.SetEnvironmentVariable("AZD_FAKE_TERMINAL_JSON", evidence.terminal);
        if (mode == "LostResponse") throw new IOException("synthetic accepted queue response was lost");
        return Reply(201, "{}");
      } else {
        status = 400; response = "{}";
      }
      Trace(new { kind = "http", method, host = uri.Host, path, status, authPresent = !String.IsNullOrEmpty(token), secretLeaked = false });
      return Reply(status, response, etag);
    }
  }
}
'@
  Set-Content -LiteralPath (Join-Path $script:fixtureScripts 'FunctionValidation.Transport.cs') -Value $fakeTransport -Encoding utf8
  $script:worker = Join-Path $script:fixtureScripts 'FunctionValidation.Worker.ps1'
  $script:pwsh = Get-Command pwsh -CommandType Application | Select-Object -First 1 -ExpandProperty Source
  $script:fakeEnvNames = @('AZD_FAKE_MODE','AZD_FAKE_TRACE_PATH','AZD_FAKE_TENANT','AZD_FAKE_OPERATOR','AZD_FAKE_SUB','AZD_FAKE_RG','AZD_FAKE_SITE','AZD_FAKE_WORKLOAD','AZD_FAKE_STORAGE','AZD_FAKE_QUEUE','AZD_FAKE_DEPLOYMENT','AZD_FAKE_SELECTOR_ETAG','AZD_FAKE_PACKAGE_ETAG','AZD_FAKE_SITE_STATE','AZD_FAKE_CLAIM_JSON','AZD_FAKE_TERMINAL_JSON')
  $script:priorFakeEnv = @{}
  foreach ($name in $script:fakeEnvNames) { $script:priorFakeEnv[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
  $script:tenant='33333333-3333-4333-8333-333333333333'
  $script:subscription='55555555-5555-4555-8555-555555555555'
  $script:operator='66666666-6666-4666-8666-666666666666'
  $script:workload='44444444-4444-4444-8444-444444444444'
  $script:deployment='22222222-2222-4222-8222-222222222222'
  $script:siteName='func-test'
  $script:storage='sttest'
  $script:queue='sthost'
  $script:selectorETag='"selector-etag"'
  $script:packageETag='"package-etag"'
}

AfterAll {
  foreach ($name in $script:fakeEnvNames) { [Environment]::SetEnvironmentVariable($name, $script:priorFakeEnv[$name], 'Process') }
}

function script:New-WorkerRequest {
  param([switch]$ReconcileOnly,[int]$DeadlineSeconds=120)
  $context=[ordered]@{schemaVersion=2;validationId='11111111-1111-4111-8111-111111111111';siteName=$script:siteName;storageAccountName=$script:storage;queueStorageAccountName=$script:queue;sourceSha256=('a'*64);configurationSha256=('b'*64);packageSha256=('c'*64);activeDeploymentId=$script:deployment;tenantId=$script:tenant;workloadIdentityId=$script:workload;runtimeVersion='7.6';deadlineUtc=[DateTimeOffset]::UtcNow.AddSeconds($DeadlineSeconds).ToString('o')}
  $binding=[ordered]@{subscriptionId=$script:subscription;resourceGroupName='rg-test';operatorObjectId=$script:operator;packageETag=$script:packageETag;selectorETag=$script:selectorETag;transport='QueueStorage';queueName='maester-validation';queueEncoding='base64'}
  [ordered]@{request=[ordered]@{context=$context;binding=$binding};receiptPath=(Join-Path $script:fixture ([guid]::NewGuid().ToString('N')+'.json'));reconcileOnly=[bool]$ReconcileOnly}
}

function script:Invoke-SyntheticWorker {
  param([Parameter(Mandatory)]$InputObject,[Parameter(Mandatory)][string]$Mode,[string]$TracePath,[string]$SiteState='Running',[string]$TokenMode='Good')
  if(-not $TracePath){$TracePath=Join-Path $script:fixture ([guid]::NewGuid().ToString('N')+'.trace')}
  $values=@{AZD_FAKE_MODE=$Mode;AZD_FAKE_TRACE_PATH=$TracePath;AZD_FAKE_TENANT=$script:tenant;AZD_FAKE_OPERATOR=$script:operator;AZD_FAKE_SUB=$script:subscription;AZD_FAKE_RG='rg-test';AZD_FAKE_SITE=$script:siteName;AZD_FAKE_WORKLOAD=$script:workload;AZD_FAKE_STORAGE=$script:storage;AZD_FAKE_QUEUE=$script:queue;AZD_FAKE_DEPLOYMENT=$script:deployment;AZD_FAKE_SELECTOR_ETAG=$script:selectorETag;AZD_FAKE_PACKAGE_ETAG=$script:packageETag;AZD_FAKE_SITE_STATE=$SiteState;AZD_FAKE_TOKEN_MODE=$TokenMode}
  $priorToken=[Environment]::GetEnvironmentVariable('AZD_FAKE_TOKEN_MODE','Process')
  foreach($name in $values.Keys){[Environment]::SetEnvironmentVariable($name,$values[$name],'Process')}
  try {
    $json=$InputObject|ConvertTo-Json -Depth 12 -Compress
    Set-Content -LiteralPath ($TracePath+'.input.json') -Value $json -NoNewline -Encoding utf8
    $task=[AzdMaesterValidation.BoundedIO]::Run($script:pwsh,$script:worker,$json,15)
    $output=$task.GetAwaiter().GetResult()
    [pscustomobject]@{Output=$output;Result=($output|ConvertFrom-Json -AsHashtable -DateKind String);TracePath=$TracePath;Input=$InputObject}
  } finally {
    foreach($name in $values.Keys){if($name -eq 'AZD_FAKE_TOKEN_MODE'){[Environment]::SetEnvironmentVariable($name,$priorToken,'Process')}else{[Environment]::SetEnvironmentVariable($name,$script:priorFakeEnv[$name],'Process')}}
  }
}

function script:Get-WorkerTrace {
  param([string]$Path)
  if(-not (Test-Path -LiteralPath $Path)){return @()}
  @(Get-Content -LiteralPath $Path|ForEach-Object {$_|ConvertFrom-Json -AsHashtable})
}

Describe 'Synthetic worker provider boundary' {
  It 'enqueues once and reconciles a completed result after HTTP 201 or a lost response (<Mode>)' -ForEach @(
    @{Mode='Queue201'},@{Mode='LostResponse'}
  ) {
    $request=New-WorkerRequest
    $run=Invoke-SyntheticWorker $request $Mode
    $trace=Get-WorkerTrace $run.TracePath
    @($trace|Where-Object kind -CEQ 'queue-post').Count|Should -Be 1
    $run.Result.ValidationPassed|Should -BeTrue
    $run.Result.InvocationTerminalConfirmed|Should -BeTrue
    $run.Result.AppStoppedConfirmed|Should -BeFalse
    $run.Output|Should -Not -Match 'synthetic-secret-never-output'
    ($trace|ConvertTo-Json -Depth 6 -Compress)|Should -Not -Match 'synthetic-secret-never-output'
    (Get-Content $request.receiptPath -Raw|ConvertFrom-Json -AsHashtable).context.validationId|Should -BeExactly $request.request.context.validationId
  }

  It 'does not replay an enqueue after an ambiguous HTTP 503' {
    $request=New-WorkerRequest -DeadlineSeconds 6
    $run=Invoke-SyntheticWorker $request 'Queue503'
    $trace=Get-WorkerTrace $run.TracePath
    @($trace|Where-Object kind -CEQ 'queue-post').Count|Should -Be 1
    $run.Result.SubmissionPossible|Should -BeTrue
    $run.Result.ExecutionComplete|Should -BeFalse
    $run.Result.FinalStatus|Should -BeExactly 'Unresolved'
    $run.Result.AppStoppedConfirmed|Should -BeFalse
  }

  It 'rejects invalid token claims before any provider request (<TokenMode>)' -ForEach @(
    @{TokenMode='WrongTokenOid'},@{TokenMode='WrongTokenAudience'}
  ) {
    $request=New-WorkerRequest
    $tracePath=Join-Path $TestDrive ([guid]::NewGuid().ToString('N')+'.trace')
    {Invoke-SyntheticWorker $request 'Queue201' -TokenMode $TokenMode -TracePath $tracePath}|Should -Throw '*Validation worker failed or timed out*'
    $trace=Get-WorkerTrace $tracePath
    # Token acquisition is synthetic and in-memory; invalid claims must fail before provider I/O.
    @($trace|Where-Object kind -CEQ 'http').Count|Should -Be 0
  }

  It 'stops wrong site storage, wrong auth, array principal and unknown preflight before enqueue (<Mode>)' -ForEach @(
    @{Mode='WrongDeploymentStorage'},@{Mode='WrongDeploymentAuth'},@{Mode='ArrayPrincipal'},@{Mode='UnknownPreflight'}
  ) {
    $request=New-WorkerRequest
    $tracePath=Join-Path $TestDrive ([guid]::NewGuid().ToString('N')+'.trace')
    {Invoke-SyntheticWorker $request $Mode -TracePath $tracePath}|Should -Throw '*Validation worker failed or timed out*'
    $trace=Get-WorkerTrace $tracePath
    @($trace|Where-Object kind -CEQ 'queue-post').Count|Should -Be 0
    (Test-Path -LiteralPath ($request.receiptPath+'.submission.json'))|Should -BeFalse
  }

  It 'refuses a pre-existing claim before appsettings or queue submission' {
    $request=New-WorkerRequest
    $run=Invoke-SyntheticWorker $request 'OccupiedClaim'
    $trace=Get-WorkerTrace $run.TracePath
    @($trace|Where-Object kind -CEQ 'queue-post').Count|Should -Be 0
    @($trace|Where-Object {$_.kind -eq 'http' -and $_.path -match '/config/appsettings/list'}).Count|Should -Be 0
    $run.Result.FinalStatus|Should -BeExactly 'EvidenceOrTargetRejected'
  }

  It 'rejects an actual host queue account mismatch before enqueuing' {
    $request=New-WorkerRequest -DeadlineSeconds 6
    $tracePath=Join-Path $script:fixture ([guid]::NewGuid().ToString('N')+'.trace')
    $run=Invoke-SyntheticWorker $request 'WrongQueueAccount' -TracePath $tracePath
    $run.Result.SubmissionPossible|Should -BeTrue
    $run.Result.ExecutionComplete|Should -BeFalse
    $run.Result.FinalStatus|Should -BeExactly 'Unresolved'
    $trace=Get-WorkerTrace $tracePath
    @($trace|Where-Object kind -CEQ 'queue-post').Count|Should -Be 0
    @($trace|Where-Object {$_.kind -eq 'http' -and $_.path -match '/config/appsettings/list'}).Count|Should -Be 1
  }

  It 'reconciles a stopped exact site from saved intent without settings reads or enqueue' {
    $request=New-WorkerRequest -ReconcileOnly
    $context=$request.request.context
    $contextJson=Get-MaesterValidationContextJson $context
    $intent=[ordered]@{schemaVersion=2;context=$context;binding=$request.request.binding;contextSha256=(Get-MaesterValidationHash $contextJson)}
    $intentJson=$intent|ConvertTo-Json -Depth 12 -Compress
    Set-Content -LiteralPath $request.receiptPath -Value $intentJson -NoNewline
    Set-Content -LiteralPath ($request.receiptPath+'.submission.json') -Value (([ordered]@{schemaVersion=2;contextSha256=$intent.contextSha256;submissionPossible=$true;recordedUtc=[DateTimeOffset]::UtcNow.ToString('o')})|ConvertTo-Json -Compress) -NoNewline
    $claim=[ordered]@{schemaVersion=2;validationId=$context.validationId;invocationId='77777777-7777-4777-8777-777777777777';contextSha256=$intent.contextSha256;status='Started';startedAt=[DateTimeOffset]::UtcNow.AddSeconds(-1).ToString('o')}
    $terminal=[ordered]@{schemaVersion=2;validationId=$context.validationId;invocationId=$claim.invocationId;contextSha256=$intent.contextSha256;status='Succeeded';startedAt=$claim.startedAt;completedAt=[DateTimeOffset]::UtcNow.ToString('o')}
    [Environment]::SetEnvironmentVariable('AZD_FAKE_CLAIM_JSON',($claim|ConvertTo-Json -Compress),'Process')
    [Environment]::SetEnvironmentVariable('AZD_FAKE_TERMINAL_JSON',($terminal|ConvertTo-Json -Compress),'Process')
    try { $run=Invoke-SyntheticWorker $request 'ReconcileStopped' -SiteState 'Stopped' }
    finally { [Environment]::SetEnvironmentVariable('AZD_FAKE_CLAIM_JSON',$script:priorFakeEnv['AZD_FAKE_CLAIM_JSON'],'Process');[Environment]::SetEnvironmentVariable('AZD_FAKE_TERMINAL_JSON',$script:priorFakeEnv['AZD_FAKE_TERMINAL_JSON'],'Process') }
    $trace=Get-WorkerTrace $run.TracePath
    $run.Result.ValidationPassed|Should -BeTrue
    $run.Result.ReconcileOnly|Should -BeTrue
    $run.Result.AppStoppedConfirmed|Should -BeFalse
    @($trace|Where-Object kind -CEQ 'queue-post').Count|Should -Be 0
    @($trace|Where-Object {$_.kind -eq 'http' -and $_.path -match '/config/appsettings/list'}).Count|Should -Be 0
    @($trace|Where-Object {$_.kind -eq 'http' -and $_.path -like '*/subscriptions/*'}).Count|Should -BeGreaterThan 0
  }
}

