# Otimização Windows 11 para jogos

Scripts PowerShell que aplicam ajustes de desempenho e latência no Windows 11, com **backup automático** e **reversão completa**.

## Como usar

1. Copie a pasta inteira para o PC (não rode direto do pendrive: o backup fica salvo dentro da pasta).
2. Dê dois cliques em **`Otimizar.bat`** e aceite o aviso de administrador.
3. Reinicie o PC.

Para desfazer tudo: **`Reverter.bat`**. Se preferir, use o ponto de restauração *"Antes da otimizacao (Claude)"* (`rstrui.exe`).

## O que é alterado

| Área | Ajuste |
|---|---|
| Segurança | Cria ponto de restauração e salva o valor original de cada ajuste em `backup\backup.json` |
| Energia | Plano *Desempenho Máximo*, sem suspensão seletiva de USB, sem economia de link PCIe |
| Jogos | Modo de Jogo ligado, Game DVR desligado, agendamento de GPU por hardware (HAGS) |
| Periféricos | Sem aceleração do mouse (mira 1:1), repetição de teclado no máximo, sem popup de Teclas de Aderência |
| Prioridade | MMCSS com prioridade alta para jogos, `SystemResponsiveness=10`, sem limitação de rede, foco no programa em primeiro plano |
| Segundo plano | Apps da Store sem execução em segundo plano, sem sugestões e anúncios do Windows ou da Bing no Iniciar |
| Telemetria | Serviços `DiagTrack` e `dmwappushservice` desativados, além de 9 tarefas agendadas de telemetria |
| Inicialização | Gera `programas_na_inicializacao.txt` para revisão manual |

## O que fica de fora (de propósito)

Ficam de fora o Defender e o Windows Update desativados, o SysMain e os ajustes de `bcdedit`. São arriscados e trazem pouco ou nenhum ganho real.

## Avisos

- Apps da Microsoft Store (WhatsApp, Teams etc.) podem não notificar com o app fechado.
- Em notebooks, o plano *Desempenho Máximo* consome mais bateria.
- Algumas atualizações do Windows podem reverter parte dos ajustes. Basta rodar o script de novo.
- Use por sua conta e risco.
