# CasaFlix

Aplicativo Flutter privado para acessar o **Jellyfin Casa** no Android e iOS.

## Baixar para Android

Baixe a versão mais recente em
[CasaFlix.apk](https://github.com/Maximuzsz/casaflix/releases/latest/download/CasaFlix.apk).
No Android, autorize a instalação de aplicativos da fonte usada para abrir o
arquivo quando o sistema solicitar.

## O que já funciona

- conexão pública por HTTPS, sem VPN ou aplicativo auxiliar;
- descoberta alternativa do servidor pela rede local;
- login Jellyfin e token guardado no armazenamento seguro do aparelho;
- bibliotecas e itens recentes;
- detalhes, sinopse, temporadas e lista de episódios;
- reprodução HLS com transcodificação H.264/AAC pelo servidor;

## Executar

```sh
flutter pub get
flutter run
```

Requer Flutter 3.38 ou mais recente. O aplicativo não inclui usuário, senha ou
token Jellyfin no código-fonte; cada aparelho autentica diretamente no servidor.

O endereço inicial é
`https://jellyfin-casa.tailfb7f41.ts.net`. Na rede de casa, o aplicativo
também tenta localizar o servidor diretamente caso o endereço público esteja
indisponível.

## Segurança

O token Jellyfin é salvo com `flutter_secure_storage`. O acesso remoto usa
HTTPS. HTTP permanece permitido apenas para a descoberta na rede local.
