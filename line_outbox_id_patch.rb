# config/initializers/line_outbox_id_patch.rb
# Chatwoot 4.5 compatibility: override Line::SendOnLineService#perform_reply
# - Keep the original delivered/failed logic (response.code == '200')
# - Enhancement: if the JSON response includes sentMessages[0].id, write it back to message.source_id
# - Use to_prepare to ensure it works after autoload/reload (production will also run once)

require 'json'

module AwLineOutboxIdPatch
  module Util
    module_function
    def extract_sent_id(resp)
      body = (resp&.body).to_s
      return nil if body.empty?
      JSON.parse(body).dig('sentMessages', 0, 'id') rescue nil
    end
  end

  module SendPatch
    private
    def perform_reply
      # Original send (based on Chatwoot 4.5 source code)
      response = channel.client.push_message(
        message.conversation.contact_inbox.source_id,
        build_payload
      )

      return if response.blank?

      parsed_json = JSON.parse(response.body) rescue {}

      if response.code == '200'
        Messages::StatusUpdateService.new(message, 'delivered').perform
      else
        # Original code includes external_error(parsed_json), keep it
        Messages::StatusUpdateService.new(message, 'failed', external_error(parsed_json)).perform
      end

      # Enhancement: write back LINE's messageId to messages.source_id
      if (sent_id = Util.extract_sent_id(response)).to_s != '' && message.source_id.to_s.strip.empty?
        message.update_column(:source_id, sent_id)
      end
    end
  end
end

Rails.application.config.to_prepare do
  if defined?(Line::SendOnLineService)
    # Always prepend to avoid public/private and load order issues
    Line::SendOnLineService.prepend(AwLineOutboxIdPatch::SendPatch) \
      unless Line::SendOnLineService.ancestors.include?(AwLineOutboxIdPatch::SendPatch)
  end
end
