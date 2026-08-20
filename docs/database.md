# Database Design

users

id
email
password_hash
partner_id
connection_pin
qr_token
is_connected
created_at

messages

id
sender_id
receiver_id
message
created_at

calls

id
caller_id
receiver_id
type
started_at
ended_at