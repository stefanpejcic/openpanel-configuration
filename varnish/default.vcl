vcl 4.1;

backend http_backend {
    .host = "127.0.0.1";
    .port = "8080";
}

backend https_backend {
    .host = "127.0.0.1";
    .port = "8443";
}

sub vcl_recv {
    if (req.http.X-Forwarded-Proto == "https") {
        set req.backend_hint = https_backend;
    } else {
        set req.backend_hint = http_backend;
    }
}

sub vcl_backend_response {
    set beresp.ttl = 5m;
}

sub vcl_deliver {
    unset resp.http.X-Powered-By;
    unset resp.http.Server;
}
