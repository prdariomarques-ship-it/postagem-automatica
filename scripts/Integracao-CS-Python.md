# Integração dos Scripts V3 do Ollama com Interfaces em C# e Python

**Autor:** Manus AI · **Data:** 16/08/2026 · **Contexto:** pacote Ollama-Local-Portatil (Windows 11, CPU-only, Ollama 0.32.9 em `http://127.0.0.1:11434`)

Este guia descreve como integrar os artefatos V3 — `Teste-Estresse-VRAM.ps1`, `Ollama-Local-V3-DuallMode.ps1` e `Ollama-Local.ps1` (V2.3) — a uma interface gráfica em **C#** ou **Python**, preservando as guards de segurança e o contrato da API local.

## 1. Princípio arquitetural

| Responsabilidade | No PowerShell V3 | Em C# (.NET 4.8 / .NET 6+) | Em Python (3.10+) |
|---|---|---|---|
| Interface gráfica | WinForms nativo | WinForms ou WPF | Tkinter, PyQt6 ou CustomTkinter |
| Envio HTTP assíncrono (Runspace) | `[runspacefactory]::CreateRunspace()` | `HttpClient` + `Task.Run` com `CancellationToken` | `asyncio` + `httpx.AsyncClient` |
| Envio HTTP APM (V2) | `HttpWebRequest.BeginGetResponse` + timer 200 ms | `HttpWebRequest.BeginGetResponse` | `threading.Thread` com `requests.post(stream=True)` |
| Cancelamento | `Abort()` (APM) ou `HttpClient` (Runspace) | `CancellationTokenSource.Cancel()` | `threading.Event` + fechar sessão |
| Guards de segurança | Regex bloqueando `:cloud`/`-cloud` | Validação no método de envio | Validação antes da requisição |
| Monitoramento VRAM/RAM | `nvidia-smi` + `ollama ps` via loop | `Process.GetProcessesByName` + contador de memória | `psutil` sobre o processo |

**Regra fundamental:** a UI nunca deve enviar a requisição diretamente. O tempo de inferência do modelo domina a latência (~11 s para 9B em CPU, ~4–20 s para 4B). Qualquer interface que bloqueie o thread principal ficará travada.

## 2. Integração em C# (WinForms)

### 2.1 Envio com CancellationToken (substitui o Runspace)

```csharp
// Guards: bloquear modelos :cloud/-cloud e hosts não-locais
private bool ValidateModel(string model, string host)
{
    if (model.IndexOf(":cloud", StringComparison.OrdinalIgnoreCase) >= 0 ||
        model.IndexOf("-cloud", StringComparison.OrdinalIgnoreCase) >= 0)
        return false;
    if (!host.StartsWith("http://127.0.0.1:11434"))
        return false;
    return true;
}

private CancellationTokenSource _cts;

private async Task<string> GenerateAsync(string model, string prompt,
    IProgress<string> tokenProgress, CancellationToken token)
{
    var url = "http://127.0.0.1:11434/api/generate";
    var body = new { model, prompt, stream = true,
        options = new { num_predict = 256, num_ctx = 2048 } };
    var json = JsonSerializer.Serialize(body);
    var content = new StringContent(json, Encoding.UTF8, "application/json");

    using var client = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };
    using var response = await client.PostAsync(url, content, token);
    response.EnsureSuccessStatusCode();

    var sb = new StringBuilder();
    using var stream = await response.Content.ReadAsStreamAsync(token);
    using var reader = new StreamReader(stream);
    while (!reader.EndOfStream)
    {
        token.ThrowIfCancellationRequested();
        var line = await reader.ReadLineAsync(token);
        if (string.IsNullOrEmpty(line)) continue;
        var chunk = JsonDocument.Parse(line).RootElement;
        if (chunk.TryGetProperty("response", out var resp))
        {
            var text = resp.GetString() ?? "";
            sb.Append(text);
            tokenProgress?.Report(text);  // atualiza a UI a cada token
        }
    }
    return sb.ToString();
}

private async void OnSendClick(object sender, EventArgs e)
{
    if (!ValidateModel(cboModel.Text, txtHost.Text))
    {
        MessageBox.Show("Modelo bloqueado ou host inválido (apenas 127.0.0.1:11434).");
        return;
    }
    _cts = new CancellationTokenSource();
    try
    {
        await GenerateAsync(cboModel.Text, txtPrompt.Text,
            new Progress<string>(t => txtOutput.AppendText(t)), _cts.Token);
    }
    catch (OperationCanceledException)
    {
        txtOutput.AppendText("\n[Cancelado pelo usuário]");
    }
    catch (Exception ex)
    {
        txtOutput.AppendText($"\n[Erro: {ex.Message}]");
    }
    finally { _cts.Dispose(); _cts = null; }
}

private void OnCancelClick(object sender, EventArgs e) => _cts?.Cancel();
```

### 2.2 Executar os scripts V3 a partir do C#

```csharp
var psi = new ProcessStartInfo
{
    FileName = "powershell.exe",
    Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden " +
                "-File \"C:\\Ollama-Local\\Teste-Estresse-VRAM.ps1\" -Iterations 3",
    RedirectStandardOutput = true, UseShellExecute = false,
    CreateNoWindow = true
};
var proc = Process.Start(psi);
string output = await proc.StandardOutput.ReadToEndAsync();
await proc.WaitForExitAsync();  // .NET 5+; em .NET 4.8 usar proc.WaitForExit()
```

### 2.3 Monitoramento de RAM em tempo real

```csharp
private void TimerMonitor_Tick(object sender, EventArgs e)
{
    var procs = Process.GetProcessesByName("llama-server")
                 .Concat(Process.GetProcessesByName("ollama"));
    long memMB = procs.Sum(p => p.WorkingSet64 / 1048576L);
    txtMemoria.Text = $"llama-server + ollama: {memMB} MB";
}
```

## 3. Integração em Python

### 3.1 Thread síncrona (estilo APM/V2, Tkinter)

```python
import requests, threading, json, tkinter as tk

ENDPOINT = "http://127.0.0.1:11434"

def validar_modelo(modelo: str) -> bool:
    return ":cloud" not in modelo.lower() and "-cloud" not in modelo.lower()

class OllamaApp:
    def __init__(self, root: tk.Tk):
        self.stop_event = threading.Event()

    def enviar(self):
        modelo = self.modelo_var.get()
        if not validar_modelo(modelo):
            self.log("[Modelo bloqueado: contém :cloud ou -cloud]")
            return
        self.stop_event.clear()
        threading.Thread(target=self._gerar,
                         args=(modelo, self.prompt.get()), daemon=True).start()

    def _gerar(self, modelo: str, prompt: str):
        try:
            r = requests.post(f"{ENDPOINT}/api/generate", json={
                "model": modelo, "prompt": prompt, "stream": True,
                "options": {"num_predict": 256, "num_ctx": 2048}},
                stream=True, timeout=600)
            r.raise_for_status()
            for line in r.iter_lines():
                if self.stop_event.is_set():
                    break
                if not line:
                    continue
                texto = json.loads(line.decode()).get("response", "")
                self.root.after(0, self.log, texto)
        except requests.exceptions.RequestException as e:
            self.root.after(0, self.log, f"[Erro: {e}]")

    def cancelar(self):
        self.stop_event.set()
```

### 3.2 Assíncrono moderno (asyncio + httpx)

```python
import asyncio, httpx, json

async def gerar(modelo: str, prompt: str, token: asyncio.Event):
    async with httpx.AsyncClient(timeout=600.0) as c:
        async with c.stream("POST", "http://127.0.0.1:11434/api/generate",
                            json={"model": modelo, "prompt": prompt,
                                  "stream": True,
                                  "options": {"num_predict": 256, "num_ctx": 2048}}) as r:
            r.raise_for_status()
            async for line in r.aiter_lines():
                if token.is_set():
                    await r.aclose()
                    break
                if not line.strip():
                    continue
                yield json.loads(line).get("response", "")

# Cancelar: token.set()
```

### 3.3 Executar scripts V3 a partir do Python

```python
import subprocess

def rodar_teste_estresse(iterations: int = 3) -> str:
    cmd = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
           "-File", r"C:\Ollama-Local\Teste-Estresse-VRAM.ps1",
           "-Iterations", str(iterations)]
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=1800)
    return r.stdout
```

## 4. Regras de segurança obrigatórias

| # | Regra | Implementação |
|---|---|---|
| 1 | Endpoint exclusivo | URL fixa `http://127.0.0.1:11434` — nunca aceitar entrada de usuário para o host |
| 2 | Bloqueio de cloud | Rejeitar modelos com `:cloud` ou `-cloud` (case-insensitive); nunca conectar a `api.ollama.com` |
| 3 | Timeout explícito | Mínimo de 10 min por requisição; cancelamento manual sempre disponível |
| 4 | Modelo único na RAM | `OLLAMA_MAX_LOADED_MODELS=1` no servidor garante descarga automática ao trocar de modelo |
| 5 | Nenhum segredo em código | Nunca embutir chaves de API, tokens ou URLs externas nos fontes versionados |

## 5. Recomendação final

| Cenário | Rota recomendada | Motivo |
|---|---|---|
| Uso pessoal, desenvolvimento rápido | Python + Tkinter/CustomTkinter (seção 3.1) | Menos boilerplate; mesma lógica do V2.3 |
| Distribuição portátil sem dependências | C# WinForms (seção 2.1) | .NET pré-instalado no Windows 11; sem pip/venv |
| Diagnóstico e benchmarks | Executar `.ps1` externamente (seção 2.2 / 3.3) | Mantém os scripts como fonte única de verdade |
