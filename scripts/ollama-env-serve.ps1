# Wrapper Ollama: aplica variaveis de otimizacao do perfil de usuario e inicia o servidor
# Gravado com UTF-8 BOM para PowerShell 5.1
foreach ($k in @("OLLAMA_MAX_LOADED_MODELS","OLLAMA_NUM_PARALLEL","OLLAMA_CONTEXT_LENGTH","OLLAMA_KEEP_ALIVE")) {
  $v = [Environment]::GetEnvironmentVariable($k, "User")
  if ($v) { [Environment]::SetEnvironmentVariable($k, $v, "Process") }
}
& "C:\Users\dario\AppData\Local\Programs\Ollama\ollama.exe" serve
