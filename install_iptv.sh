#!/bin/bash
# ==============================================================================
# 🚀 Instalador Completo - Koffice Pro v2.3 (Modo PHP NATIVO para Ubuntu 26.04)
# ==============================================================================

clear
echo "======================================================="
echo "🚀 Instalador Office Xtream (Ubuntu 26.04)"
echo "======================================================="
sleep 2

# === CONFIGURAÇÕES ===
read -p "🌍 Digite o domínio do painel (ex: painel.brtvs.top): " DOMAIN
read -p "📧 Digite o e-mail para SSL/alertas (ex: admin@${DOMAIN}): " ADMIN_EMAIL
[ -z "$ADMIN_EMAIL" ] && ADMIN_EMAIL="admin@${DOMAIN}"

DB_NAME="kofficepro"
DB_USER="user_kofficepro"
DB_PASS="pass_kofficepro"
ROOT_DB_PASS="root123"

PAINEL_URL="https://github.com/Jeanroot/iptv-kofficeproAtualizado/releases/download/v1.0/kofficexui.zip"
SQL_URL="https://github.com/Jeanroot/iptv-kofficeproAtualizado/releases/download/v1.0/kofficexui_sql.zip"
WWW_DIR="/var/www/html"
BACKUP_DIR="/var/backups/officextream"

# === 0. LIMPEZA TOTAL DA INSTALAÇÃO ANTIGA ===
echo "🧹 Passo 0/10: Limpando a instalação antiga..."
systemctl stop apache2 >/dev/null 2>&1
umount -f ${WWW_DIR}/streams >/dev/null 2>&1 || true

rm -rf ${WWW_DIR}/*
rm -rf /usr/share/phpmyadmin
rm -rf ${BACKUP_DIR}
rm -f /usr/local/bin/officextream_backup.sh
rm -f /etc/apache2/sites-available/${DOMAIN}.conf
rm -f /etc/apache2/sites-enabled/${DOMAIN}.conf
crontab -r 2>/dev/null

systemctl start mariadb >/dev/null 2>&1
mariadb -u root -e "DROP DATABASE IF EXISTS ${DB_NAME}; DROP USER IF EXISTS '${DB_USER}'@'localhost';" >/dev/null 2>&1
mariadb -u root -p"${ROOT_DB_PASS}" -e "DROP DATABASE IF EXISTS ${DB_NAME}; DROP USER IF EXISTS '${DB_USER}'@'localhost';" >/dev/null 2>&1
sleep 1

# === 1. RESTAURAÇÃO E INSTALAÇÃO COM PHP NATIVO ===
echo "🔧 Passo 1/10: Limpando repositórios e preparando o sistema..."
export DEBIAN_FRONTEND=noninteractive

rm -f /etc/apt/sources.list.d/*php*.list
rm -f /etc/apt/sources.list.d/*ondrej*.list
rm -f /etc/apt/sources.list.d/*sury*.list

apt-get update -y >/dev/null 2>&1
apt-get --fix-broken install -y >/dev/null 2>&1
apt-get install -y curl wget unzip cron >/dev/null 2>&1

debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
debconf-set-selections <<< "postfix postfix/mailname string $DOMAIN"

echo "📦 Instalando pacotes do sistema (Apache, MariaDB, FFmpeg)..."
apt-get install -y apache2 mariadb-server ufw ffmpeg certbot python3-certbot-apache mailutils postfix >/dev/null 2>&1

echo "📦 Instalando PHP Nativo do sistema..."
apt-get install -y php php-cli php-mysql php-curl php-xml php-mbstring php-zip php-gd libapache2-mod-php

INSTALLED_PHP=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
echo "✅ Versão do PHP detectada: $INSTALLED_PHP"

a2dismod mpm_event mpm_worker 2>/dev/null
a2enmod mpm_prefork 2>/dev/null
a2enmod php${INSTALLED_PHP} >/dev/null 2>&1

systemctl restart apache2 >/dev/null 2>&1
sleep 1

# === TRAVA DE SEGURANÇA ===
PHP_INI="/etc/php/${INSTALLED_PHP}/apache2/php.ini"
if [ ! -f "$PHP_INI" ]; then
    echo "❌ FATAL ERRO: O PHP não foi instalado corretamente."
    exit 1
fi
echo "✅ Dependências instaladas com SUCESSO!"
sleep 1

# === 2. CONFIGURANDO O FIREWALL ===
echo "🔒 Passo 2/10: Configurando o firewall..."
ufw allow ssh >/dev/null 2>&1
ufw allow 80/tcp >/dev/null 2>&1
ufw allow 443/tcp >/dev/null 2>&1
ufw allow 8080/tcp >/dev/null 2>&1
ufw --force enable >/dev/null 2>&1

apt-get install -y ipset iptables >/dev/null 2>&1
iptables -A INPUT -p tcp --syn --dport 80 -m connlimit --connlimit-above 50 --connlimit-mask 32 -j REJECT --reject-with tcp-reset
iptables -A INPUT -p tcp --syn --dport 443 -m connlimit --connlimit-above 50 --connlimit-mask 32 -j REJECT --reject-with tcp-reset
echo "✅ Firewall ativado com proteção Anti-DDoS."
sleep 1

# === 3. CONFIGURAÇÕES DO PHP ===
echo "⚙️ Passo 3/10: Ajustando limites do PHP ${INSTALLED_PHP}..."
sed -i "s/upload_max_filesize = .*/upload_max_filesize = 800M/" $PHP_INI
sed -i "s/post_max_size = .*/post_max_size = 800M/" $PHP_INI
sed -i "s/memory_limit = .*/memory_limit = 1024M/" $PHP_INI
sed -i "s/max_execution_time = .*/max_execution_time = 600/" $PHP_INI
sed -i "s/max_input_time = .*/max_input_time = 600/" $PHP_INI
systemctl restart apache2
echo "✅ Limites ajustados."
sleep 1

# === 4. INSTALANDO PHPMYADMIN ===
echo "🧩 Passo 4/10: Instalando o phpMyAdmin..."
cd /usr/share/ && rm -rf phpmyadmin
wget -q https://files.phpmyadmin.net/phpMyAdmin/5.2.1/phpMyAdmin-5.2.1-all-languages.zip -O phpmyadmin.zip
unzip -q phpmyadmin.zip && mv phpMyAdmin-5.2.1-all-languages phpmyadmin && rm phpmyadmin.zip
chown -R www-data:www-data phpmyadmin && chmod -R 755 phpmyadmin

cat <<EOF > /etc/apache2/conf-available/phpmyadmin.conf
Alias /phpmyadmin /usr/share/phpmyadmin
<Directory /usr/share/phpmyadmin>
    Options FollowSymLinks
    DirectoryIndex index.php
    AllowOverride All
    Require all granted
</Directory>
EOF

a2enconf phpmyadmin >/dev/null 2>&1 && a2enmod rewrite >/dev/null 2>&1
echo "✅ phpMyAdmin instalado."
sleep 1

# === 5. CONFIGURANDO BANCO DE DADOS ===
echo "🗄️ Passo 5/10: Configurando MariaDB e limites turbo..."
bash -c 'cat >> /etc/mysql/my.cnf <<EOF
[mysqld]
max_allowed_packet = 1024M
sql_mode = ""
wait_timeout = 28800
interactive_timeout = 28800
EOF' 2>/dev/null

bash -c 'cat >> /etc/mysql/mariadb.conf.d/50-server.cnf <<EOF
max_allowed_packet = 1024M
sql_mode = ""
wait_timeout = 28800
interactive_timeout = 28800
EOF' 2>/dev/null

systemctl restart mariadb && systemctl enable mariadb >/dev/null 2>&1

mariadb -u root >/dev/null 2>&1 <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${ROOT_DB_PASS}';
DROP USER IF EXISTS ''@'localhost';
DROP DATABASE IF EXISTS test;
FLUSH PRIVILEGES;
EOF

mariadb -u root -p"${ROOT_DB_PASS}" >/dev/null 2>&1 <<EOF
DROP DATABASE IF EXISTS ${DB_NAME};
CREATE DATABASE ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
DROP USER IF EXISTS '${DB_USER}'@'localhost';
CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOF

wget -q "${SQL_URL}" -O /tmp/banco_iptv.zip
mkdir -p /tmp/sql_ext && rm -rf /tmp/sql_ext/*
if unzip -oq /tmp/banco_iptv.zip -d /tmp/sql_ext >/dev/null 2>&1; then
    SQL_FILE=$(find /tmp/sql_ext -type f -name "*.sql" | head -n 1)
    if [ -n "$SQL_FILE" ]; then
        mariadb -u root -p"${ROOT_DB_PASS}" ${DB_NAME} < "$SQL_FILE" 2>/dev/null
    fi
else
    mariadb -u root -p"${ROOT_DB_PASS}" ${DB_NAME} < /tmp/banco_iptv.zip 2>/dev/null
fi
rm -rf /tmp/sql_ext /tmp/banco_iptv.zip
echo "✅ Base de dados criada com sucesso."
sleep 1

# === 6. INSTALANDO O PAINEL E RAM DISK ===
echo "💻 Passo 6/10: Instalando ficheiros na raiz..."
wget -q "${PAINEL_URL}" -O /tmp/painel.zip
mkdir -p /tmp/painel_ext
unzip -o /tmp/painel.zip -d /tmp/painel_ext >/dev/null 2>&1

shopt -s dotglob
if [ $(ls -1 /tmp/painel_ext | wc -l) -eq 1 ] && [ -d /tmp/painel_ext/*/ ]; then
    cp -a /tmp/painel_ext/*/* ${WWW_DIR}/
else
    cp -a /tmp/painel_ext/* ${WWW_DIR}/
fi
shopt -u dotglob
rm -rf /tmp/painel_ext /tmp/painel.zip

chown -R www-data:www-data ${WWW_DIR} && chmod -R 755 ${WWW_DIR}
echo "✅ Painel instalado na raiz."

echo "💾 Configurando o RAM Disk (8GB)..."
mkdir -p ${WWW_DIR}/streams
rm -rf ${WWW_DIR}/streams/*
cp /etc/fstab /etc/fstab.bak
sed -i "\|${WWW_DIR}/streams|d" /etc/fstab
echo "tmpfs ${WWW_DIR}/streams tmpfs defaults,noatime,nosuid,size=8G 0 0" >> /etc/fstab
systemctl daemon-reload >/dev/null 2>&1
mount -a
echo "✅ RAM Disk ativo!"
sleep 1

# === 7. DOMÍNIO E SSL ===
echo "🌐 Passo 7/10: Gerando SSL via Certbot..."
VHOST_FILE="/etc/apache2/sites-available/${DOMAIN}.conf"
cat <<EOF > $VHOST_FILE
<VirtualHost *:80>
    ServerName ${DOMAIN}
    DocumentRoot ${WWW_DIR}
    DirectoryIndex index.php index.html
    <Directory ${WWW_DIR}>
        Options FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

a2ensite 000-default.conf >/dev/null 2>&1
a2ensite ${DOMAIN}.conf >/dev/null 2>&1
systemctl restart apache2 && systemctl enable apache2 >/dev/null 2>&1

certbot --apache --non-interactive --agree-tos -d ${DOMAIN} -m ${ADMIN_EMAIL} --redirect
echo "✅ Domínio seguro com SSL."
sleep 1

# === 8. HLS MULTIPLEX ===
echo "🎥 Passo 8/10: Configurando sistema HLS Multiplex..."
mkdir -p ${WWW_DIR}/api
mkdir -p ${WWW_DIR}/streams

cat << 'PHP' > ${WWW_DIR}/api/ts_wrapper.php
<?php
error_reporting(0);
$file = $_GET['file'] ?? '';
$ip = $_SERVER['REMOTE_ADDR'];

$base_dir = realpath(__DIR__ . '/../streams/');
$real_path = realpath($base_dir . '/' . $file);

if ($real_path && strpos($real_path, $base_dir) === 0 && file_exists($real_path)) {
    require_once '../includes/db.php';
    if (session_status() === PHP_SESSION_ACTIVE) { session_write_close(); }

    if (preg_match('/canal_([0-9]+)/', $file, $matches)) {
        $channel_id = $matches[1];
        try {
            $pdo->prepare("UPDATE active_connections SET start_time = ? WHERE user_ip = ? AND content_id = ? AND stream_type = 'live'")->execute([time(), $ip, $channel_id]);
        } catch (Exception $e) {}
    }

    $pdo = null;

    header('Content-Type: video/mp2t');
    header('Content-Length: ' . filesize($real_path));
    header('Cache-Control: no-cache, no-store, must-revalidate');

    if (ob_get_level()) { ob_end_clean(); }
    flush();

    readfile($real_path);
    exit;
}
http_response_code(404);
?>
PHP
chmod 644 ${WWW_DIR}/api/ts_wrapper.php

cat << 'HTACCESS' > ${WWW_DIR}/streams/.htaccess
RewriteEngine On
RewriteCond %{REQUEST_FILENAME} \.ts$
RewriteRule ^(.*)$ ../api/ts_wrapper.php?file=$1 [L,QSA]
HTACCESS
chmod 644 ${WWW_DIR}/streams/.htaccess

cat << EOF > /etc/apache2/conf-available/hls-override.conf
<Directory ${WWW_DIR}/streams/>
    AllowOverride All
</Directory>
EOF
a2enconf hls-override >/dev/null 2>&1
a2enmod rewrite >/dev/null 2>&1
echo "✅ HLS otimizado."
sleep 1

# === 9. ROTINAS CRON ===
echo "🔄 Passo 9/10: Injetando rotinas automáticas (Cron)..."
mkdir -p ${BACKUP_DIR}

cat <<EOF > /usr/local/bin/officextream_backup.sh
#!/bin/bash
TIMESTAMP=\$(date +"%Y-%m-%d_%H-%M")
BACKUP_DIR="${BACKUP_DIR}"
DB_NAME="${DB_NAME}"
DB_USER="${DB_USER}"
DB_PASS="${DB_PASS}"
ADMIN_EMAIL="${ADMIN_EMAIL}"
SQL_FILE="\$BACKUP_DIR/db_\$TIMESTAMP.sql.gz"
FILES_FILE="\$BACKUP_DIR/files_\$TIMESTAMP.tar.gz"
mysqldump -u"\$DB_USER" -p"\$DB_PASS" "\$DB_NAME" | gzip > \$SQL_FILE
tar -czf \$FILES_FILE -C /var/www html
echo "Backup automático concluído." | mail -a "From: backup@\$DOMAIN" -s "Backup Xtream - \$DOMAIN - \$TIMESTAMP" -A "\$SQL_FILE" -A "\$FILES_FILE" "\$ADMIN_EMAIL"
find \$BACKUP_DIR -type f -name "*.gz" -mtime +7 -delete
EOF
chmod +x /usr/local/bin/officextream_backup.sh

echo "<?php if(php_sapi_name()!=='cli')die(); require_once __DIR__.'/config.php'; \$pdo=getConexaoAtiva(); exec('ipset create painel_blocks hash:ip 2>/dev/null'); exec('iptables -C INPUT -m set --match-set painel_blocks src -j DROP 2>/dev/null || iptables -I INPUT -m set --match-set painel_blocks src -j DROP'); exec('ipset flush painel_blocks'); \$ips=\$pdo->query('SELECT ip FROM blocked_ips')->fetchAll(PDO::FETCH_COLUMN); foreach(\$ips as \$ip) { \$ip=trim(\$ip); if(filter_var(\$ip,FILTER_VALIDATE_IP)) exec('ipset add painel_blocks '.escapeshellarg(\$ip).' 2>/dev/null'); } ?>" > /var/www/html/sync_firewall.php

crontab -r 2>/dev/null
(
    echo "5 4 * * * /usr/local/bin/officextream_backup.sh >/dev/null 2>&1"
    echo "5 16 * * * /usr/local/bin/officextream_backup.sh >/dev/null 2>&1"
    echo "0 * * * * /usr/bin/php ${WWW_DIR}/epg_importer.php >/dev/null 2>&1"
    echo "*/5 * * * * /usr/bin/php ${WWW_DIR}/watchdog_cron.php >/dev/null 2>&1"
    echo "0 9 * * * /usr/bin/php ${WWW_DIR}/robo_cobranca.php >/dev/null 2>&1"
    echo "* * * * * /usr/bin/php /var/www/html/sync_firewall.php > /dev/null 2>&1"
    echo "0 4 * * * sync; echo 3 > /proc/sys/vm/drop_caches"
) | crontab -

echo "✅ Cronjobs criados."
sleep 1

# === 10. FINALIZAÇÃO ===
echo "✉️ Passo 10/10: Iniciando os serviços finais..."
systemctl restart apache2 mariadb postfix && systemctl enable postfix >/dev/null 2>&1

EMAIL_BODY=$(cat <<EOF
Instalação do painel Koffice Pro concluída.

DADOS DO PHPMYADMIN
Link: https://${DOMAIN}/phpmyadmin
Utilizador: root
Palavra-passe: ${ROOT_DB_PASS}

DADOS DA BASE DE DADOS
Nome: ${DB_NAME}
Utilizador: ${DB_USER}
Palavra-passe: ${DB_PASS}
EOF
)

echo "$EMAIL_BODY" | mail -a "From: admin@${DOMAIN}" -s "✅ Instalação Office Xtream - ${DOMAIN}" "$ADMIN_EMAIL"

clear
echo "======================================================"
echo "✅ INSTALAÇÃO CONCLUÍDA NO UBUNTU 26.04!"
echo "======================================================"
echo "Os dados foram enviados para o e-mail: ${ADMIN_EMAIL}"
echo
echo "🌍 phpMyAdmin: https://${DOMAIN}/phpmyadmin"
echo "👤 Utilizador: root / 🔑 Palavra-passe: ${ROOT_DB_PASS}"
echo
echo "🗄️ Banco: ${DB_NAME} | 👤 User: ${DB_USER} | 🔑 Senha: ${DB_PASS}"
echo
echo "🌍 Painel: https://${DOMAIN}"
echo "👤 Utilizador: admin / 🔑 Palavra-passe: admin"
echo "======================================================"
