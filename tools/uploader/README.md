# NetPobre Enviar

Aplicativo Windows para selecionar vídeos e enviá-los diretamente às
bibliotecas do servidor NetPobre por SFTP.

## Uso

1. Abra `NetPobre-Enviar.exe`.
2. Escolha `Filmes`, `Séries` ou `Vídeos pessoais`.
3. Selecione arquivos soltos ou uma pasta inteira.
4. Opcionalmente informe uma subpasta, como
   `Ted Lasso/Temporada 03`.
5. Clique em **Enviar agora**.

O programa mantém a organização de pastas, verifica espaço livre, envia para
um arquivo temporário e só publica o nome definitivo depois de validar o
tamanho. Se a conexão cair, a parte já transferida é reaproveitada na próxima
tentativa. O Jellyfin monitora as bibliotecas e reconhece os vídeos enviados.

## Segurança

O executável não contém senha. Ele usa a chave dedicada
`~/.ssh/netpobre_uploader_ed25519`, criada apenas no notebook autorizado. A
chave pública correspondente fica no servidor.

## Desenvolvimento

```powershell
python -m unittest tools/uploader/test_uploader.py
powershell -ExecutionPolicy Bypass -File tools/uploader/build.ps1
```
