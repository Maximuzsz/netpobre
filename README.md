# NetPobre

Aplicativo Flutter privado para acessar o servidor doméstico **NetPobre** no
Android e iOS.

## Baixar para Android

Baixe a versão mais recente em
[NetPobre.apk](https://github.com/Maximuzsz/netpobre/releases/latest/download/NetPobre.apk).
No Android, autorize a instalação de aplicativos da fonte usada para abrir o
arquivo quando o sistema solicitar.

## O que já funciona

- conexão pública por HTTPS, sem VPN ou aplicativo auxiliar;
- troca automática para a conexão direta na rede local;
- login Jellyfin e token guardado no armazenamento seguro do aparelho;
- bibliotecas e itens recentes;
- navegação por Início, Busca e Minha Lista;
- busca por filmes, séries e episódios;
- títulos e sinopses em português, com o título original preservado;
- atualização de metadados em português pelo menu da conta;
- favoritos sincronizados com o servidor;
- faixa Continuar assistindo e retomada no ponto exato em qualquer aparelho;
- detalhes, sinopse, temporadas e lista de episódios;
- reprodução HLS com transcodificação H.264/AAC pelo servidor;
- reprodução móvel otimizada em 720p com limite de 3 Mb/s;
- controles para avançar ou voltar 10 segundos e indicador de carregamento.
- próximo episódio com contagem e reprodução automática;
- seleção de áudio, legenda e qualidade entre 480p, 720p e 1080p;
- botões para pular abertura, resumo e créditos quando disponíveis;
- miniaturas de navegação geradas pelo Jellyfin;
- recomendações e faixa A seguir;
- múltiplos perfis Jellyfin com histórico independente;
- login por código para televisão e navegação por controle remoto;
- downloads para reprodução offline no aparelho.

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
