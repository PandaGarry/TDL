class_name SessionTransport
extends RefCounted
## Transport seam between GameSession and a concrete network backend.
##
## Transports move opaque packets only. They do not interpret game
## messages, own world state, assign player bodies or decide whether an
## intent is valid: those remain GameSession responsibilities. The first
## backend is ENet; a future Steam/local/test backend can implement this
## contract without rewriting the authoritative simulation.

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal packet_received(peer_id: int, packet: PackedByteArray)
signal connected_to_server
signal connection_failed
signal server_disconnected


func host(_port: int, _max_peers: int) -> Error:
	push_warning("SessionTransport.host() is not implemented by this backend")
	return ERR_UNAVAILABLE


func join(_address: String, _port: int) -> Error:
	push_warning("SessionTransport.join() is not implemented by this backend")
	return ERR_UNAVAILABLE


func poll() -> void:
	pass


func send_packet(_peer_id: int, _packet: PackedByteArray, _reliable: bool = true) -> Error:
	return ERR_UNAVAILABLE


func broadcast_packet(packet: PackedByteArray, reliable: bool = true) -> Error:
	return send_packet(0, packet, reliable)


func disconnect_peer(_peer_id: int) -> void:
	pass


func close() -> void:
	pass


func get_unique_id() -> int:
	return 0


func is_active() -> bool:
	return false


func is_server() -> bool:
	return false


func get_peers() -> PackedInt32Array:
	return PackedInt32Array()
