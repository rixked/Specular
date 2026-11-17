# Test fixtures

`self_signed_cert.pem` and `self_signed_key.pem` are a throwaway self-signed
certificate for `localhost`, used only by `certificate_pinning_test.dart` to
run a local HTTPS server. The key protects nothing; never use it elsewhere.

SHA-256 fingerprint:
`A2:ED:3C:AF:26:CD:BD:4B:E5:88:2B:91:A7:71:51:CC:94:E0:69:B4:6E:F9:AA:56:09:E4:01:52:E3:7A:05:C1`
