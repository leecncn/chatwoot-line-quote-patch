# z_line_quote_and_outbox_id_patch.rb
# Feature 1 (Inbound / display):
#   Render a gray “quote preview” block when LINE replies are received.
#   - If the quoted message contains media: show thumbnail for images, a playable link for videos (via proxy URL).
# Feature 2 (Outbound):
#   After sending a LINE message, write LINE's `sentMessages[0].id` back to `Message#source_id`
#   so future LINE replies can correctly match the agent message.
# Note:
#   This file does NOT touch your ActiveStorage/Attachment/proxy setup; it only handles quote rendering and outbound id backfill.

require 'json'

# === Feature 1: Inbound — quote preview (gray block + media fallback) ===
module LineQuoteMessageContentPatch
  def message_content(event)
    text = super

    # Use the real quoted message id. `quoteToken` appears on most events and cannot be used to detect quoting.
    quoted_id = event.dig('message', 'quotedMessageId') ||
                event.dig('message', 'quote', 'messageId')
    return text unless quoted_id.present?

    # Limit lookup to the same inbox to avoid cross-inbox/channel mismatches.
    inbox_id = @inbox&.id if instance_variable_defined?(:@inbox)
    relation = ::Message.joins(:conversation)
    relation = relation.where(conversations: { inbox_id: inbox_id }) if inbox_id
    quoted_msg = relation.find_by(source_id: quoted_id.to_s)

    header_text, media_md = build_preview_for(quoted_msg, quoted_id)

    # Gray block contains one-line summary; media (thumbnail/link) goes in the next paragraph.
    header_block = "```\n#{header_text}\n```"

    [header_block, media_md, text].compact.join("\n\n").strip
  end

  private

  def build_preview_for(quoted_msg, quoted_id)
    if quoted_msg
      sender = quoted_msg&.sender&.name.presence || '訪客'

      if quoted_msg.attachments.any?
        att  = quoted_msg.attachments.first
        blob = att.try(:file)&.blob
        ct   = blob&.content_type.to_s

        if ct.start_with?('image/')
          header_text = "#{sender}: [圖片]"
          thumb = safe_thumbnail_url(att)
          media_md = thumb.present? ? "![引用圖片縮圖](#{thumb})" : nil
          [header_text, media_md]
        elsif ct.start_with?('video/')
          header_text = "#{sender}: [影片]"
          url = safe_attachment_url(att)
          media_md = url.present? ? "▶ 影片（點我播放）：#{url}" : nil
          [header_text, media_md]
        else
          label = att.try(:file_type) || '附件'
          header_text = "#{sender}: [#{label}]"
          media_md = safe_attachment_url(att)
          [header_text, media_md]
        end
      elsif quoted_msg.content.present?
        ["#{sender}: #{truncate_text(quoted_msg.content)}", nil]
      else
        ["#{sender}: [無文字內容]", nil]
      end
    else
      # Fallback when the agent's message didn't have source_id recorded yet.
      ["代理訊息（尚未記錄 messageId）(ID: #{quoted_id.to_s[0..8]}…)", nil]
    end
  end

  def safe_thumbnail_url(att)
    att.respond_to?(:thumbnail_url) ? att.thumbnail_url : nil
  end

  def safe_attachment_url(att)
    att.respond_to?(:url) ? att.url : nil
  end

  def truncate_text(text)
    ActionController::Base.helpers.truncate(text.to_s, length: 40)
  end
end

# === Feature 2: Outbound — write LINE sentMessages[].id into Message#source_id ===
module LineOutboxSourceIdPatch
  private

  # Intercept common send paths; if a method doesn't exist in a given version, it will be ignored.
  def deliver(*args)
    response = super
    attach_sent_message_id_to_source!(response)
    response
  end

  def push_message(client, to, messages)
    response = super
    attach_sent_message_id_to_source!(response)
    response
  end

  def reply_message(client, reply_token, messages)
    response = super
    attach_sent_message_id_to_source!(response)
    response
  end

  # Persist sentMessages[0].id into current @message.source_id (if present).
  def attach_sent_message_id_to_source!(response)
    msg = instance_variable_defined?(:@message) ? @message : nil
    return unless msg && msg.respond_to?(:update_columns)

    body_str = extract_body_string(response)
    return if body_str.blank?

    begin
      data = JSON.parse(body_str) rescue nil
      sent_id = data && data.dig('sentMessages', 0, 'id')
      msg.update_columns(source_id: sent_id) if sent_id.present?
    rescue
      # silent fail; never affect main flow
    end
  end

  def extract_body_string(response)
    if response.respond_to?(:body)
      response.body.to_s
    elsif response.is_a?(Hash)
      response.to_json
    else
      response.to_s
    end
  rescue
    nil
  end
end

Rails.application.config.to_prepare do
  # Inbound hook: render quote preview on LINE inbound messages
  if defined?(::Line::IncomingMessageService)
    ::Line::IncomingMessageService.prepend(LineQuoteMessageContentPatch)
  end

  # Outbound hook: backfill source_id after sending
  if defined?(::Channel::Line::MessageBuilder)
    ::Channel::Line::MessageBuilder.prepend(LineOutboxSourceIdPatch)
  end
end
