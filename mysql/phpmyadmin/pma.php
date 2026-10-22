<?php

require_once '/etc/phpmyadmin/config.secret.inc.php';
setcookie('pma_manual_user', '', time() - 3600, '/', '', false, true);

$providedToken = $_GET['token'] ?? '';
$username      = $_GET['user']  ?? '';

if (empty($username) || empty($providedToken)) {
    header("Location: ./index.php");
    exit;
}

if (!preg_match('/^[a-zA-Z0-9_-]+$/', $username)) {
    header("Location: ./index.php?invalid");
    exit;
}

$tokenFile = '/home/' . $username . '/pma.token';
if (!file_exists($tokenFile)) {
    header("Location: ./index.php?invalid");
    exit;
}

$fileToken = trim(file_get_contents($tokenFile));
if (strlen($fileToken) < 32 || !hash_equals($fileToken, $providedToken)) {
    header("Location: ./index.php?invalid");
    exit;
}

$socketPath = '/home/' . $username . '/sockets/mysqld/mysqld.sock';
if (!file_exists($socketPath)) {
    header("Location: ./index.php?invalid");
    exit;
}

$envFile = '/home/' . $username . '/.env';
$envVars = parse_ini_file($envFile);
$mysqlPassword = $envVars['MYSQL_ROOT_PASSWORD'] ?? '';
if (empty($mysqlPassword)) {
    header("Location: ./index.php?invalid");
    exit;
}

$serverIndex = 1;
foreach (glob('/home/*/sockets/mysqld/mysqld.sock') as $i => $sock) {
    $sockUser = explode('/', $sock)[2];
    if ($sockUser === $username) {
        $serverIndex = $i + 1;
        break;
    }
}

// the image's /sessions can be missing, then fall back to the temp dir, config.inc.php picks the same so phpMyAdmin finds this session
$sessionPath = session_save_path();
if ($sessionPath === '' || !(is_dir($sessionPath) || @mkdir($sessionPath, 01733, true)) || !is_writable($sessionPath)) {
    session_save_path(sys_get_temp_dir());
}

$sessionName = 'OPENPANEL_PMA_' . strtoupper($username);
session_set_cookie_params(0, '/', '', false, true);
session_name($sessionName);
session_start();

$_SESSION['PMA_single_signon_user']     = 'root';
$_SESSION['PMA_single_signon_password'] = $mysqlPassword;
$_SESSION['PMA_single_signon_host']     = 'localhost';

session_write_close();

setcookie('pma_manual_user', '', time() - 3600, '/', '', false, true);

header("Location: ./index.php?server=" . $serverIndex);
exit;
