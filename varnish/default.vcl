vcl 4.1;

backend default {
    .host = "VARNISH_BACKEND_HOST";
    .port = "80";
    .max_connections = 2048;
}

# Define an access control list to restrict cache purging.
acl purge {
  "127.0.0.1";
  "192.168.0.0"/16;
}

sub vcl_hit {
    if (req.http.X-Forwarded-Proto == "https") {
        set req.http.X-Forwarded-Proto = "https";
    } else {
        set req.http.X-Forwarded-Proto = "http";
    }

    if (obj.ttl > 0s) {
        return (deliver);
    }
    if (obj.ttl + obj.grace > 0s) {
        return (deliver);
    }

    return (miss);  # Use "miss" instead of "fetch"
}

sub vcl_recv {
  if (req.method == "PURGE") {
    if (!client.ip ~ purge) {
      return(synth(405, "Not allowed."));
    }
    return (purge);
  }

  if (req.method != "GET" && req.method != "HEAD" && req.method != "PUT" &&
      req.method != "POST" && req.method != "TRACE" && req.method != "OPTIONS" &&
      req.method != "PATCH" && req.method != "DELETE") {
    return (pipe);
  }

  if (req.http.Upgrade ~ "(?i)websocket") {
    return (pipe);
  }

  if (req.method != "GET" && req.method != "HEAD") {
    return (pass);
  }

  if (req.http.Authorization) {
    return (pass);
  }

  if (req.url~ "^/wp-admin/") {
    return (pass);
  }

  if (req.url ~ "#") {
    set req.url = regsub(req.url, "#.*$", "");
  }

  if (req.http.cookie) {
    if (req.url ~ "preview") {
      return (pass);
    } else {
      unset req.http.cookie;
    }
  }

  return (hash);
}

sub vcl_pipe {
  if (req.http.upgrade) {
    set bereq.http.upgrade = req.http.upgrade;
  }
  return (pipe);
}

sub vcl_backend_response {
  if (beresp.status == 500 || beresp.status == 502 || beresp.status == 503 || beresp.status == 504) {
    return (abandon);
  }
  if (bereq.url ~ "^[^?]*\\.(bmp|bz2|css|doc|eot|flv|gif|gz|ico|jpe?g|js|less|mp[34]|otf|pdf|png|rar|rtf|swf|tar|tgz|ttf|txt|wav|webm|woff|xml|zip)(\\?.*)?$") {
    unset beresp.http.set-cookie;
  }

  if (beresp.status == 301 || beresp.status == 302) {
    set beresp.http.location = regsub(beresp.http.location, ":[0-9]+", "");
  }

  if (beresp.ttl <= 0s || beresp.http.set-cookie || beresp.http.vary == "*") {
    set beresp.ttl = 120s;
    set beresp.uncacheable = true;
    return (deliver);
  }

  set beresp.grace = 6h;
  return (deliver);
}

sub vcl_deliver {
### uncomment to remove from responses ###
#  unset resp.http.X-Powered-By;
#  unset resp.http.Server;
#  unset resp.http.server;
#  unset resp.http.via;
#  unset resp.http.x-powered-by;
#  unset resp.http.x-runtime;
#  unset resp.http.x-varnish;

  return (deliver);
}
