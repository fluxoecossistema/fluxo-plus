# Supabase: autenticação, sincronização e backup

O Fluxo+ continua offline-first. O Supabase é opcional e armazena um snapshot
JSON do banco local por usuário. Cada usuário só acessa o próprio backup por
meio de Row Level Security (RLS).

## Configuração

1. Crie um projeto no Supabase.
2. Abra o SQL Editor e execute `supabase/schema.sql`. O script também prepara
   as assinaturas Premium com RLS e acesso somente para leitura pelo cliente.
3. Em Authentication, habilite Email/Password.
4. Em Authentication → URL Configuration, defina:
   - Site URL: `https://github.com/LINCOLN201/Fluxo-Plus`
   - Redirect URLs: `https://github.com/LINCOLN201/Fluxo-Plus`
5. Copie a Project URL e a Publishable Key.
6. Para um build local:

```powershell
flutter build apk --release `
  --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=SUA_CHAVE_PUBLICA
```

Para releases automáticas, adicione os Actions Secrets:

- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

A chave usada no cliente deve ser a **Publishable Key**, nunca `service_role`.

## Operação

- O usuário cria uma conta ou entra em Configurações → Backup na nuvem.
- Com confirmação de e-mail ativa, use apenas o link mais recente. Links
  expirados ou já utilizados retornam `otp_expired`.
- **Fazer backup agora** grava o snapshot imediatamente. Se o backup da conta
  for mais recente do que os dados do aparelho, o aplicativo pergunta qual
  versão manter em vez de sobrescrever.
- **Restaurar do backup** substitui os dados do aparelho, sempre com
  confirmação e guardando uma cópia local para **Desfazer**.
- O aplicativo também sincroniza ao abrir, ao voltar do segundo plano e ao ir
  para o segundo plano (com limite de 8 segundos). Essas passagens nunca
  perguntam nada e nunca apagam dados por conta própria.

### Quem sobrescreve quem

A decisão é do `SyncPlanner` (`lib/core/sync/sync_planner.dart`), que compara:
a conta ligada ao aparelho, o `updated_at` do backup visto na última
sincronização e um hash canônico dos dados locais. Esses três valores ficam na
tabela local `settings` e nunca entram no snapshot enviado.

| Situação | Decisão |
| --- | --- |
| Aparelho ligado a outra conta, com dados criados aqui | Pergunta ao usuário |
| Conta sem backup e aparelho sem nada criado | Nada a fazer |
| Conta sem backup e aparelho com dados | Envia |
| Existe backup e o aparelho não tem nada criado | Restaura |
| Ligado à conta, nuvem intocada, nada mudou aqui | Nada a fazer |
| Ligado à conta, nuvem intocada, mudou aqui | Envia |
| Ligado à conta, outro aparelho gravou, nada mudou aqui | Restaura |
| Ligado à conta, outro aparelho gravou e mudou aqui | Pergunta ao usuário |
| Primeira sincronização, backup igual aos dados daqui | Só vincula |
| Primeira sincronização, backup diferente | Pergunta ao usuário |

"Sem nada criado" significa nenhuma transação, nenhuma meta e as contas e
categorias iniciais intactas (`AppDatabase.isPristine`).

Falhas de rede ou de servidor não interrompem o uso: ficam registradas em
`last_backup_error` e aparecem em Configurações com a opção de tentar de novo.

## Premium

A tabela `premium_subscriptions` não aceita gravações vindas do APK ou do
aplicativo Windows. Futuramente, somente um webhook seguro do provedor de
pagamentos deverá alterar plano, status e período de validade. O cliente
consulta apenas a assinatura do próprio usuário e mantém um cache local para
continuar funcionando offline.

O modelo atual guarda um snapshot por conta e resolve divergências perguntando
ao usuário. Sincronização granular, com resolução de conflitos por registro,
pode ser adicionada numa versão futura.
