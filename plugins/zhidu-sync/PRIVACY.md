# Zhidu Sync Privacy

This plugin requires a Zhidu account. Connecting opens the Zhidu authorization
page in your browser. Your password is entered on that page, never collected by
this plugin. Authorization uses a one-use code and PKCE S256, with the read-only
scope `obsidian.sync.read`. No Cookie, App JWT, MCP token or LLM key is requested
from the user.

Requests go only to the API origin compiled into this build. Release builds
default to https://api.youxugarden.com; acceptance builds explicitly display the
test origin in settings. No analytics, advertising, telemetry, third-party AI
services or automatic background network requests are included.

The plugin reads book metadata, reading progress, highlights, thoughts, saved
AI explanations/questions, tags and timestamps. It excludes book files, local
file/cover paths, free notes and full AI conversations. It does not send vault
notes to Zhidu or write reading data back to Zhidu.

Access tokens and pending PKCE verifiers are saved only through Obsidian's
official SecretStorage API, in installation-specific keys. They are never put
in plugin data.json, Markdown, logs, build artifacts or release packages. This
does not imply isolation from other installed plugins: Obsidian plugins are
trusted code, and SecretStorage is a shared host facility. Consult Obsidian's
current documentation for its platform-specific storage protections. No
additional encryption guarantees are claimed by this plugin.

Reading data is written to Markdown in your own Vault. Plugin data.json also
contains an entity cache, file identity/hash receipts, cursor and an in-flight
write journal, including reading text. These files are not encrypted by this
plugin; protect the Vault, backups and any external Vault sync service you use.

Disconnect first revokes the integration token at Zhidu, then clears its value
from SecretStorage and removes the local sync cache/checkpoint. It does not
delete Markdown. If the server cannot be reached, disconnection does not claim
successful revocation; it leaves the credential available to retry. Existing
backend tokens expire after 24 hours. Uninstalling the plugin alone is not a
server-side revocation: disconnect before uninstalling. SecretStorage may retain
empty key names after credentials have been cleared.

Authorization callbacks use the OS-registered obsidian:// URI. Only a matching,
unexpired state initiated by this installation can exchange the code. Browsers
and operating systems may retain their own navigation history; callback codes
are one-use, short-lived and PKCE-bound. Plugin errors do not print those codes.

This project is not an official Obsidian product or partnership.
