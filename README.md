# chatwoot-line-quote-patch
Allow LINE messages to be quoted in Chatwoot

## Overview
This repository provides three initializer patches for Chatwoot:

- **line_outbox_id_patch.rb**  
  Ensures that outbound LINE messages (sent by Agents) store the correct `messageId` into `messages.source_id`.

- **line_webhook_backfill.rb**  
  When a LINE webhook contains a `quotedMessageId`, this patch backfills the referenced Agent message’s `source_id` *before* creating the inbound message.

- **z_line_inbound_quote_patch.rb**  
  Adds a textual **quote preview** to message content when a LINE reply is detected (based on `quotedMessageId`).

Together these patches allow LINE replies (text, images, videos) to display correctly inside Chatwoot.

## Installation
1. Copy the `.rb` files into your Chatwoot instance under `config/initializers/`.
2. If running with Docker, mount them via `docker-compose.override.yml`:

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

## License
This patch set is released under the GNU Affero General Public License v3.0 (AGPLv3),
the same license as [Chatwoot](https://github.com/chatwoot/chatwoot).
