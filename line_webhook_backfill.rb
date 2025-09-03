# v3: Attach backfill logic to Line::IncomingMessageService,
# ensuring the replied message's source_id is populated
# *before* the inbound message is created.
# Enhancements: ±120s time window, expanded scan size, media-first selection to reduce mismatches.

module AwLineWebhookBackfill
  module_function

  def backfill!(conversation, event)
    return unless conversation && event.is_a?(Hash)

    qid  = event.dig('message', 'quotedMessageId')
    qtxt = event.dig('message', 'quotedMessage', 'text')
    return unless qid.present?

    # Convert event timestamp (ms → Time) for time window checks, to avoid duplicate mis-matches
    ts_ms = event['timestamp'].to_i
    ts    = ts_ms.positive? ? Time.at(ts_ms / 1000.0) : nil

    scope = conversation.messages
                        .where(sender_type: 'Agent')
                        .where('source_id IS NULL OR source_id = ?', '')
                        .order(created_at: :desc)
                        .limit(50) # increased from 20 to 50 for safety

    # Restrict to ±120s window (120s before, 10s after as tolerance)
    if ts
      scope = scope.where('created_at BETWEEN ? AND ?', ts - 120, ts + 10)
    end

    candidate =
      if qtxt.present?
        # When text exists, try exact match first; otherwise fall back to most recent
        scope.detect { |m| m.content.to_s.strip == qtxt.to_s.strip } || scope.first
      else
        # For pure media replies (no text), prioritize messages with attachments, else fallback
        scope.detect { |m| m.attachments.loaded? ? m.attachments.any? : m.attachments.exists? } || scope.first
      end

    candidate&.update_column(:source_id, qid)
  end
end

# --- Dynamically prepend backfill into IncomingMessageService ---
if defined?(Line::IncomingMessageService)
  # Dynamically wrap available methods to avoid super-missing issues
  candidate_methods = [:perform, :process, :process_event, :run, :execute]

  base  = Line::IncomingMessageService
  patch = Module.new

  candidate_methods.each do |meth|
    next unless base.instance_methods(false).include?(meth)

    patch.define_singleton_method(:__define_hook_for__) do |m|
      define_method(m) do |*args, &blk|
        # Attempt to extract event from different contexts/arguments
        event = nil
        event ||= (defined?(@event) && @event.is_a?(Hash)) ? @event : nil
        event ||= args.find { |a| a.is_a?(Hash) }
        # Chatwoot services typically have @conversation already set
        conversation = (defined?(@conversation) && @conversation) ? @conversation : nil

        begin
          AwLineWebhookBackfill.backfill!(conversation, event) if event && conversation
        rescue StandardError
          # Fail silently, avoid impacting main flow
        end

        super(*args, &blk)
      end
    end

    patch.__send__(:__define_hook_for__, meth)
  end

  base.prepend(patch) if patch.instance_methods(false).any?
end
