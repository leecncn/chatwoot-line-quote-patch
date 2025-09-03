# Chatwoot LINE Quote Patch

![Unofficial](https://img.shields.io/badge/status-unofficial-blue)
![License: AGPL v3](https://img.shields.io/badge/license-AGPLv3-green)
![Tested on Chatwoot 4.5](https://img.shields.io/badge/tested%20on-Chatwoot%204.5-orange)

## Overview
This is an **unofficial** patch set for Chatwoot’s LINE channel.  
It adds two key features:

1. **Inbound Quote Preview**  
   Display quoted LINE messages in Chatwoot (with a gray block preview).
2. **Outbound Message ID Backfill**  
   Store LINE’s `sentMessages[0].id` into `message.source_id` for proper reply mapping.

> **Disclaimer**  
> This project is not affiliated with or endorsed by Chatwoot or LINE.  
> Provided **AS IS** without warranties or guarantees of any kind. Use at your own risk.

## Installation
1. Copy the patch files into `config/initializers/`.
2. Rebuild/restart your Chatwoot container or service.

   ```yaml
   services:
     rails:
       volumes:
         - ./line_outbox_id_patch.rb:/app/config/initializers/line_outbox_id_patch.rb:ro
         - ./line_webhook_backfill.rb:/app/config/initializers/line_webhook_backfill.rb:ro
         - ./z_line_inbound_quote_patch.rb:/app/config/initializers/z_line_inbound_quote_patch.rb:ro
     sidekiq:
       volumes:
         - ./line_outbox_id_patch.rb:/app/config/initializers/line_outbox_id_patch.rb:ro
         - ./line_webhook_backfill.rb:/app/config/initializers/line_webhook_backfill.rb:ro
         - ./z_line_inbound_quote_patch.rb:/app/config/initializers/z_line_inbound_quote_patch.rb:ro

## Restart Chatwoot:
docker compose up -d --force-recreate

## Compatibility
- Works with any Chatwoot deployment (self-hosted, Elestio, Docker, etc.) as long as the LINE channel is enabled.
- Tested on Chatwoot 4.5.

## How to uninstall
rm config/initializers/z_line_inbound_quote_patch.rb
rm config/initializers/line_outbox_id_patch.rb
rm config/initializers/line_webhook_backfill.rb
# restart Chatwoot
docker compose restart rails sidekiq

## License
This patch set is released under the GNU Affero General Public License v3.0 (AGPLv3),
the same license as [Chatwoot](https://github.com/chatwoot/chatwoot).
