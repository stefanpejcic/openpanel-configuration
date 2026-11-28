<?php
/*
Plugin Name: Force SSL behind Varnish
Description: Forces SSL for wp-admin, to avoid CORS errors behind Varnish Caching in OpenPanel.
Version: 1.0
Plugin URI: https://openpanel.com/docs/articles/docker/https-wordpress-behind-varnish-proxy/
Author: Stefan Pejcic
*/

defined('ABSPATH') || exit;
define('FORCE_SSL_ADMIN', true);

add_action('init', function() {
    if (isset($_SERVER['HTTP_X_FORWARDED_PROTO']) && $_SERVER['HTTP_X_FORWARDED_PROTO'] === 'https') {
        $_SERVER['HTTPS'] = 'on';
    }
});

// WordPress only reads WP_AUTO_UPDATE_CORE itself, the plugin and theme constants set from OpenPanel are applied here
if (defined('WP_AUTO_UPDATE_PLUGINS') && WP_AUTO_UPDATE_PLUGINS === true) {
    add_filter('auto_update_plugin', '__return_true');
}
if (defined('WP_AUTO_UPDATE_THEMES') && WP_AUTO_UPDATE_THEMES === true) {
    add_filter('auto_update_theme', '__return_true');
}
