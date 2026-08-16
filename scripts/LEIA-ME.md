# Ollama Local — Pacote Portátil para Windows

## Changelog

| Versão | Descrição |
|--------|-----------|
| V3 (comparativa) | Artefatos opcionais para comparar Runspace e APM, sem substituir a V2 estável do aplicativo. |
| V2.3 | Dark theme verde-escuro + stream em tempo real via Runspace. Tokens exibidos palavra a palavra; contador ao vivo; timeout de 90 s. |
| V2.1 | Redesign da interface: tema escuro, paleta verde-escura (#0B1812), layout por camadas. |
| V2 | Envio assíncrono com cancelamento seguro; janela permanece responsiva durante a inferência; codificação UTF-8 com BOM. |
| V1 | Versão inicial com interface WinForms e envio síncrono. |

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
| `Ollama-Local-V3-DuallMode.ps1` | Interface opcional de comparação, iniciada com `-Mode Runspace` ou `-Mode APM`. Não substitui `Ollama-Local.ps1`. |
| `Teste-Estresse-VRAM.ps1` | Bateria comparativa local de tempo, VRAM e cancelamento entre os modos Runspace e APM. |
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

## Modelos recomendados (CPU-only, 16 GB RAM)

Testado em 16/08/2026 com Ollama v0.32.9, CPU x86, VRAM = 0 GB.

| Prioridade | Modelo | RAM (Q4) | Tempo médio | Notas |
|------------|--------|----------|-------------|-------|
| **1 — padrão** | `phi4-mini` | ~2,3 GB | **1,5–6 s** (quente) / ~17 s (frio) | 0 falhas; 3,7 tok/s; sem suporte a imagens |
| 2 — multimodal | `qwen3.5:4b` | ~3,0 GB | ~17 s (quente) / ~37 s (frio) | Imagem + texto, 256K contexto; usar `num_predict ≥ 256` em análise de imagem |
| 3 — alternativa | `qwen3:4b` | ~3,0 GB | 19 s | Thinking/rápido; instável com RAM cheia (3 timeouts) |
| 4 — mais leve | `llama3.2:3b` | ~2,2 GB | — | Mais rápido; ideal para respostas curtas e tool calls |
| 5 | `gemma3:4b` | ~3,0 GB | — | Multimodal; 140+ idiomas; já instalado |

Para definir o modelo padrão permanentemente:
```powershell
[System.Environment]::SetEnvironmentVariable('OLLAMA_MODEL','phi4-mini','User')
```

Para instalar o phi4-mini:
```
ollama pull phi4-mini
```

## Variáveis de ambiente respeitadas

| Variável | Padrão | Descrição |
|----------|--------|-----------|
| `OLLAMA_MODEL` | (nenhum) | Modelo pré-selecionado ao abrir a interface |
| `OLLAMA_CONTEXT_LENGTH` | `2048` | Tokens de contexto por requisição (menor = menos RAM) |
| `OLLAMA_KEEP_ALIVE` | `5m` (padrão Ollama) | Retenção do modelo na RAM; **não altere para 0** em uso sequencial — modelo quente responde 9× mais rápido (1,5 s vs 13 s) |
| `OLLAMA_MAX_LOADED_MODELS` | `1` | Descarrega automaticamente o modelo anterior ao carregar um novo — recomendado em hardware com menos de 8 GB de RAM |
| `OLLAMA_HOST` | `http://127.0.0.1:11434` | Endpoint do servidor (não altere para URL remota) |

## Análise de imagens

Apenas modelos multimodais aceitam imagens. O `phi4-mini` retorna erro 400 ao receber imagem — use o `qwen3.5:4b` ou `gemma3:4b`.

| Situação | Procedimento |
|----------|-------------|
| Trocar para análise de imagem | Clique "Liberar VRAM", selecione `qwen3.5:4b` no menu |
| Resposta vazia com imagem | Aumente `num_predict` para 256–512 no body da requisição |
| Voltar ao chat normal | Clique "Liberar VRAM", selecione `phi4-mini` |

O `OLLAMA_MAX_LOADED_MODELS=1` automatiza a descarga do modelo anterior ao trocar.

## Stream em tempo real (V2.3)

A partir da V2.3, as respostas são exibidas **palavra a palavra** assim que o modelo as gera, sem esperar o fim da inferência.

- **Tokens ao vivo:** um contador no rodapé mostra quantos tokens foram gerados até o momento.
- **Botão "Cancelar resposta":** interrompe a requisição HTTP imediatamente; a interface volta ao estado pronto em segundos.
- **Timeout interno:** 90 segundos sem token novo cancela automaticamente e exibe mensagem de erro.
- **Durante a geração:** o campo de prompt e o botão "Enviar" ficam desabilitados; apenas "Cancelar resposta" fica ativo.

## Modelos locais recomendados (CPU-only, 16 GB RAM — dados de 16/08/2026)

| Modelo | RAM (Q4) | Uso | Latência medida |
|--------|----------|-----|------------------|
| `phi4-mini` | ~2,5 GB | **Padrão** — chat no dia a dia | 1,5–1,7 s (modelo na RAM) · 12 s (frio) |
| `qwen3.5:4b` | ~2,9 GB | Multimodal — análise de **imagens** + contexto longo (256K) | 16,9 s imagem (64 tok) · 84 s (256 tok) |
| `qwen3:4b` | ~3 GB | Alternativa de texto | 18,9 s médio · instável sob pressão de RAM |

Observações importantes:
- O **phi4-mini não analisa imagens** (rejeita requisições com imagem — erro 400). Para imagens, use o `qwen3.5:4b`.
- Em tarefas de imagem, o `qwen3.5:4b` escreve a análise no campo interno de raciocínio (`thinking`). Na API, aumente `num_predict` para 256+ ou capture o `thinking` no stream.
- Modelos na RAM respondem ~9× mais rápido. Use **[4] Liberar VRAM** (ou `keep_alive=0`) apenas quando precisar de RAM livre.

## Comparação opcional Runspace × APM (V3)

A V2 (`Ollama-Local.ps1`) continua sendo a interface principal recomendada. Ela usa APM (`HttpWebRequest.BeginGetResponse`) com timer de 200 ms e cancelamento por `Abort()`.

A V3 é um artefato de avaliação: ela oferece os dois mecanismos de execução, sempre contra o mesmo Ollama local em `127.0.0.1:11434`.

| Modo | Comando | Mecanismo | Cancelamento |
|------|---------|-----------|--------------|
| Runspace | `powershell -ExecutionPolicy Bypass -File .\Ollama-Local-V3-DuallMode.ps1 -Mode Runspace` | `Invoke-RestMethod` dentro de runspace dedicado + timer de 300 ms | `Stop()` do pipeline PowerShell |
| APM | `powershell -ExecutionPolicy Bypass -File .\Ollama-Local-V3-DuallMode.ps1 -Mode APM` | `HttpWebRequest.BeginGetResponse` + timer de 200 ms | `Abort()` da requisição HTTP |

Para medir as diferenças no computador que realmente possui a GPU, abra o PowerShell na pasta `scripts` e execute:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Teste-Estresse-VRAM.ps1 -Iterations 10
```

O teste utiliza somente os modelos locais listados pela API do Ollama e rejeita nomes terminados em `:cloud` ou contendo `-cloud:`. Ele mede o tempo de resposta de cada modo, consulta o uso de VRAM em `/api/ps` e exercita o cancelamento após três segundos. O teste pode manter o modelo carregado após uma requisição; use `Liberar VRAM` ou aguarde o `OLLAMA_KEEP_ALIVE` se quiser descarregar o modelo.

> Não compare resultados do sandbox ou de outro computador. VRAM e desempenho só são significativos na máquina Windows que possui a GPU usada pelo Ollama.

## Solução de problemas

| Problema | Causa provável | Solução |
|----------|---------------|---------|
| "Serviço Ollama não encontrado" | Ollama não está rodando | Abra o app Ollama ou execute `ollama serve` |
| "Nenhum modelo instalado" | Sem modelos locais | `ollama pull phi4-mini` (verifique espaço em disco) |
| Interface abre e fecha rápido | Erro de PowerShell | Execute `Abrir-Ollama-Local.cmd` pelo Prompt de Comando para ver a mensagem |
| nvidia-smi não encontrado | Driver Nvidia não instalado | Instale o driver Nvidia; sem GPU usa CPU (mais lento) |
| Modelo na CPU (100% CPU) | VRAM insuficiente | Use modelo menor ou feche outros aplicativos |
