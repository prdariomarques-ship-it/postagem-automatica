# Ollama Local — Pacote Portátil para Windows

Interface de linha de comando para usar o Ollama inteiramente local no Windows.
Sem nuvem, sem chaves de API, sem instaladores adicionais.

## Pré-requisitos

| Requisito | Verificação |
|-----------|-------------|
| Windows 10/11 | — |
| Ollama instalado | `ollama --version` no PowerShell |
| PowerShell 5.1+ | Já incluso no Windows 10/11 |
| Ao menos um modelo local | `ollama list` |
| GPU Nvidia (opcional) | `nvidia-smi` no PowerShell |

## Arquivos do pacote

| Arquivo | Descrição |
|---------|-----------|
| `Abrir-Ollama-Local.cmd` | **Abre a interface.** Clique duplo ou execute no Explorer. |
| `Ollama-Local.ps1` | Interface principal (PowerShell). Não execute diretamente — use o `.cmd` acima. |
| `Testar-Ollama-Local.cmd` | Diagnóstico rápido: versão, serviço, modelos, GPU, inferência de teste. |
| `Monitorar-VRAM.cmd` | Monitor ao vivo de VRAM e GPU. Abra em janela separada durante inferência. |
| `LEIA-ME.md` | Este arquivo. |

## Como usar

### 1. Abrir a interface principal

Dê duplo clique em `Abrir-Ollama-Local.cmd`.

No menu que aparece:
- **[1] Enviar prompt** — envie uma mensagem ao modelo selecionado.
- **[2] Selecionar modelo** — escolha entre os modelos instalados localmente.
- **[3] Importar GGUF local** — crie um modelo a partir de um arquivo `.gguf` já no seu computador.
- **[4] Liberar VRAM** — descarregue modelos da memória imediatamente.
- **[5] Diagnóstico** — veja `ollama ps`, status do serviço e telemetria GPU.

### 2. Diagnóstico rápido

```
Testar-Ollama-Local.cmd
```

Para testar um modelo específico, defina `OLLAMA_MODEL` antes de executar.  
No **Prompt de Comando** (cmd.exe):
```cmd
set OLLAMA_MODEL=qwen3:4b && Testar-Ollama-Local.cmd
```
No **PowerShell**:
```powershell
$env:OLLAMA_MODEL = "qwen3:4b"; cmd /c Testar-Ollama-Local.cmd
```

### 3. Monitorar VRAM durante inferência

Abra `Monitorar-VRAM.cmd` em uma janela separada **antes** de enviar um prompt pela interface.
Observe as colunas `PROCESSOR` do `ollama ps` e `memory.used` do `nvidia-smi` (se disponível).
Pare com **Ctrl+C** quando terminar.

### 4. Importar arquivo GGUF

1. Abra a interface (`Abrir-Ollama-Local.cmd`).
2. Escolha **[3] Importar GGUF local**.
3. Informe o caminho completo do arquivo `.gguf` (ex: `C:\Modelos\llama-3.gguf`).
4. Informe um nome local (ex: `llama3-local:q4`). Não use `:cloud` ou `-cloud`.
5. Aguarde a criação — pode levar alguns minutos conforme o tamanho do arquivo.

## Segurança e privacidade

- **Endpoint:** somente `http://127.0.0.1:11434` — nenhuma URL externa é usada.
- **Chaves de API:** nenhuma é solicitada, armazenada ou transmitida.
- **Modelos cloud:** nomes com `:cloud` ou `-cloud` são bloqueados automaticamente.
- **Rede:** nenhum tráfego de saída além do loopback local.
- **Git:** nenhum commit, push ou publicação automática.

## Variáveis de ambiente respeitadas

| Variável | Padrão | Descrição |
|----------|--------|-----------|
| `OLLAMA_MODEL` | (nenhum) | Modelo pré-selecionado ao abrir a interface |
| `OLLAMA_CONTEXT_LENGTH` | `4096` | Tokens de contexto por requisição |
| `OLLAMA_HOST` | `http://127.0.0.1:11434` | Endpoint do servidor (não altere para URL remota) |

## Solução de problemas

| Problema | Causa provável | Solução |
|----------|---------------|---------|
| "Serviço Ollama não encontrado" | Ollama não está rodando | Abra o app Ollama ou execute `ollama serve` |
| "Nenhum modelo instalado" | Sem modelos locais | `ollama pull qwen3:4b` (verifique espaço em disco) |
| Interface abre e fecha rápido | Erro de PowerShell | Execute `Abrir-Ollama-Local.cmd` pelo Prompt de Comando para ver a mensagem |
| nvidia-smi não encontrado | Driver Nvidia não instalado | Instale o driver Nvidia; sem GPU usa CPU (mais lento) |
| Modelo na CPU (100% CPU) | VRAM insuficiente | Use modelo menor ou feche outros aplicativos |
