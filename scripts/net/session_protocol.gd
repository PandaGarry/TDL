class_name SessionProtocol
extends RefCounted
## Versioned, JSON-safe wire protocol for authoritative game sessions.
##
## Packets are UTF-8 JSON rather than binary Variants. That keeps network
## input on the same explicit JSON boundary as definitions and saves and
## avoids ever decoding arbitrary Godot Objects from a peer. P0 worlds
## are intentionally tiny; delta compression belongs to a later network
## optimisation pass after real sizes are measured.

const PROTOCOL_VERSION := 1
const MAX_PACKET_BYTES := 1048576

const KIND_HELLO := "hello"
const KIND_WELCOME := "welcome"
const KIND_INTENT := "intent"
const KIND_SNAPSHOT := "snapshot"
const KIND_EVENT := "event"
const KIND_REJECT := "reject"
const KIND_PING := "ping"
const KIND_PONG := "pong"
const KIND_SERVER_STOPPING := "server_stopping"

const INTENT_MOVE_BODY := "move_body"
const INTENT_INTERACT_OBJECT := "interact_object"

const _MESSAGE_KEYS: Array[String] = ["protocol_version", "kind", "tick", "payload"]
const _INTENT_KEYS: Array[String] = ["intent_type", "client_sequence", "payload"]


static func make_message(kind: String, tick: int, payload: Dictionary = {}) -> Dictionary:
	return {
		"protocol_version": PROTOCOL_VERSION,
		"kind": kind,
		"tick": maxi(tick, 0),
		"payload": JsonValue.duplicate_safe(payload),
	}


static func make_intent(
	intent_type: String, client_sequence: int, payload: Dictionary = {}
) -> Dictionary:
	return {
		"intent_type": intent_type,
		"client_sequence": maxi(client_sequence, 0),
		"payload": JsonValue.duplicate_safe(payload),
	}


static func validate_message(message: Variant) -> Dictionary:
	if typeof(message) != TYPE_DICTIONARY:
		return _message_failure("session message must be a dictionary")
	var typed_message: Dictionary = message
	if not _has_only_keys(typed_message, _MESSAGE_KEYS):
		return _message_failure("session message has missing or unknown fields")
	if not JsonValue.is_safe(typed_message):
		return _message_failure("session message is not JSON-safe")

	var version := _integral_value(typed_message.get("protocol_version", null))
	if not bool(version.get("ok", false)) or int(version.get("value", 0)) != PROTOCOL_VERSION:
		return _message_failure("unsupported session protocol version")
	var kind := _string_value(typed_message.get("kind", null))
	if not _is_known_kind(kind):
		return _message_failure("unknown session message kind")
	var tick := _integral_value(typed_message.get("tick", null))
	if not bool(tick.get("ok", false)) or int(tick.get("value", -1)) < 0:
		return _message_failure("session message tick must be a non-negative integer")
	var payload: Variant = typed_message.get("payload", null)
	if typeof(payload) != TYPE_DICTIONARY:
		return _message_failure("session message payload must be a dictionary")

	return {
		"ok": true,
		"message": make_message(kind, int(tick.get("value", 0)), payload),
		"kind": kind,
		"tick": int(tick.get("value", 0)),
		"payload": JsonValue.duplicate_safe(payload),
		"error": "",
	}


static func validate_intent(intent: Variant) -> Dictionary:
	if typeof(intent) != TYPE_DICTIONARY:
		return _intent_failure("intent must be a dictionary")
	var typed_intent: Dictionary = intent
	if not _has_only_keys(typed_intent, _INTENT_KEYS):
		return _intent_failure("intent has missing or unknown fields")
	if not JsonValue.is_safe(typed_intent):
		return _intent_failure("intent is not JSON-safe")

	var intent_type := _string_value(typed_intent.get("intent_type", null))
	if intent_type != INTENT_MOVE_BODY and intent_type != INTENT_INTERACT_OBJECT:
		return _intent_failure("unknown intent type")
	var sequence := _integral_value(typed_intent.get("client_sequence", null))
	if not bool(sequence.get("ok", false)) or int(sequence.get("value", 0)) < 1:
		return _intent_failure("intent client_sequence must be a positive integer")
	var payload: Variant = typed_intent.get("payload", null)
	if typeof(payload) != TYPE_DICTIONARY:
		return _intent_failure("intent payload must be a dictionary")

	return {
		"ok": true,
		"intent": make_intent(intent_type, int(sequence.get("value", 0)), payload),
		"intent_type": intent_type,
		"client_sequence": int(sequence.get("value", 0)),
		"payload": JsonValue.duplicate_safe(payload),
		"error": "",
	}


static func encode_message(message: Dictionary) -> PackedByteArray:
	var report := validate_message(message)
	if not bool(report.get("ok", false)):
		return PackedByteArray()
	var packet := JSON.stringify(report.get("message", {})).to_utf8_buffer()
	if packet.size() > MAX_PACKET_BYTES:
		return PackedByteArray()
	return packet


static func decode_packet(packet: PackedByteArray) -> Dictionary:
	if packet.is_empty():
		return _message_failure("session packet is empty")
	if packet.size() > MAX_PACKET_BYTES:
		return _message_failure("session packet exceeds the maximum size")
	var parser := JSON.new()
	if parser.parse(packet.get_string_from_utf8()) != OK:
		return _message_failure("session packet is not valid JSON: %s" % parser.get_error_message())
	return validate_message(parser.data)


static func _is_known_kind(kind: String) -> bool:
	return (
		kind
		in [
			KIND_HELLO,
			KIND_WELCOME,
			KIND_INTENT,
			KIND_SNAPSHOT,
			KIND_EVENT,
			KIND_REJECT,
			KIND_PING,
			KIND_PONG,
			KIND_SERVER_STOPPING,
		]
	)


static func _has_only_keys(value: Dictionary, required_keys: Array[String]) -> bool:
	if value.size() != required_keys.size():
		return false
	for key in value.keys():
		if typeof(key) != TYPE_STRING or not required_keys.has(String(key)):
			return false
	return true


static func _integral_value(value: Variant) -> Dictionary:
	match typeof(value):
		TYPE_INT:
			var int_value := int(value)
			if int_value >= -JsonValue.MAX_SAFE_INTEGER and int_value <= JsonValue.MAX_SAFE_INTEGER:
				return {"ok": true, "value": int_value}
		TYPE_FLOAT:
			var float_value := float(value)
			if (
				is_finite(float_value)
				and float_value == floorf(float_value)
				and absf(float_value) <= float(JsonValue.MAX_SAFE_INTEGER)
			):
				return {"ok": true, "value": int(float_value)}
	return {"ok": false, "value": 0}


static func _string_value(value: Variant) -> String:
	return String(value) if typeof(value) == TYPE_STRING else ""


static func _message_failure(error: String) -> Dictionary:
	return {
		"ok": false,
		"message": {},
		"kind": "",
		"tick": -1,
		"payload": {},
		"error": error,
	}


static func _intent_failure(error: String) -> Dictionary:
	return {
		"ok": false,
		"intent": {},
		"intent_type": "",
		"client_sequence": 0,
		"payload": {},
		"error": error,
	}
