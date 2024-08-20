vcl 4.1;

backend default {
    .host = "nginx";
    .port = "2024";
}

sub vcl_recv {
    set req.backend_hint = default;
}

sub vcl_backend_response {
    set beresp.ttl = 5m;
}
