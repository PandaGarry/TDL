class_name EnetSessionTransport
extends SessionTransport
## ENet backend for SessionTransport using a session-owned MultiplayerAPI.
##
## Each endpoint creates its own `SceneMultiplayer` through
## `MultiplayerAPI.create_default_interface()` and polls it manually. The
## game therefore does not depend on the SceneTree's default multiplayer
## singleton, RPC node paths or automatic node replication. Packets use
## `SceneMultiplayer.send_bytes()` and are interpreted only by
## GameSession/SessionProtocol.
##
## `server_relay` is disabled deliberately: clients talk to the host, and
## only the authoritative host decides what state or events other peers
## receive.

const MAX_PEERS := 32
const CHANNEL_COUNT := 2
const RELIABLE_CHANNEL := 0
const UNRELIABLE_CHANNEL := 1

var _api: SceneMultiplayer
var _peer: ENetMultiplayerPeer
var _is_server := false


func host(port: int, max_peers: int) -> Error:
	if port < 1 or port > 65535 or max_peers < 1 or max_peers > MAX_PEERS:
		return ERR_INVALID_PARAMETER
	close()
	if not _create_api():
		return ERR_UNAVAILABLE
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_server(port, max_peers, CHANNEL_COUNT)
	if error != OK:
		close()
		return error
	_api.multiplayer_peer = _peer
	_is_server = true
	return OK


func join(address: String, port: int) -> Error:
	if address.strip_edges().is_empty() or port < 1 or port > 65535:
		return ERR_INVALID_PARAMETER
	close()
	if not _create_api():
		return ERR_UNAVAILABLE
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_client(address.strip_edges(), port, CHANNEL_COUNT)
	if error != OK:
		close()
		return error
	_api.multiplayer_peer = _peer
	_is_server = false
	return OK


func poll() -> void:
	if is_active():
		_api.poll()


func send_packet(peer_id: int, packet: PackedByteArray, reliable: bool = true) -> Error:
	if not is_active():
		return ERR_UNCONFIGURED
	if packet.is_empty() or peer_id < 0:
		return ERR_INVALID_PARAMETER
	var mode := (
		MultiplayerPeer.TRANSFER_MODE_RELIABLE
		if reliable
		else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
	)
	var channel := RELIABLE_CHANNEL if reliable else UNRELIABLE_CHANNEL
	return _api.send_bytes(packet, peer_id, mode, channel)


func disconnect_peer(peer_id: int) -> void:
	if is_active() and _is_server and peer_id > 1:
		_api.disconnect_peer(peer_id)


func close() -> void:
	if _peer != null:
		_peer.close()
	if _api != null:
		_api.multiplayer_peer = null
	_peer = null
	_api = null
	_is_server = false


func get_unique_id() -> int:
	return _api.get_unique_id() if is_active() else 0


func is_active() -> bool:
	return _api != null and _peer != null and _api.has_multiplayer_peer()


func is_server() -> bool:
	return is_active() and _is_server


func get_peers() -> PackedInt32Array:
	return _api.get_peers() if is_active() else PackedInt32Array()


func _create_api() -> bool:
	var created := MultiplayerAPI.create_default_interface() as SceneMultiplayer
	if created == null:
		return false
	_api = created
	_api.server_relay = false
	_api.peer_connected.connect(_on_api_peer_connected)
	_api.peer_disconnected.connect(_on_api_peer_disconnected)
	_api.peer_packet.connect(_on_api_peer_packet)
	_api.connected_to_server.connect(_on_api_connected_to_server)
	_api.connection_failed.connect(_on_api_connection_failed)
	_api.server_disconnected.connect(_on_api_server_disconnected)
	return true


func _on_api_peer_connected(peer_id: int) -> void:
	peer_connected.emit(peer_id)


func _on_api_peer_disconnected(peer_id: int) -> void:
	peer_disconnected.emit(peer_id)


func _on_api_peer_packet(peer_id: int, packet: PackedByteArray) -> void:
	packet_received.emit(peer_id, packet)


func _on_api_connected_to_server() -> void:
	connected_to_server.emit()


func _on_api_connection_failed() -> void:
	connection_failed.emit()


func _on_api_server_disconnected() -> void:
	server_disconnected.emit()
