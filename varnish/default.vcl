vcl 4.1;

backend default {
    .host = "127.0.0.1";
    .port = "80";
}

sub vcl_recv {
    set req.backend_hint = default;
}

sub vcl_backend_response {
    set beresp.ttl = 5m;
}


sub vcl_deliver {
}
