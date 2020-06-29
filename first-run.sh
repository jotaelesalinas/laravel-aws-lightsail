############################################################################
# constants
############################################################################

CONFIG_FILE=config.ini
PHP_VER=7.3

# do not modify anything from now on!

ERRCODE_CONFIG_READ_FILE=1
ERRCODE_CONFIG_MISSING_ENVS=2
ERRCODE_APT_UPDATE=3
ERRCODE_APT_INSTALL=4
ERRCODE_COPY_UPDATE_SH=5

############################################################################
# functions
############################################################################

log() {
    datestring=`date +'%Y-%m-%d %H:%M:%S'`
    # Expand escaped characters, wrap at 70 chars, indent wrapped lines
    echo -e "[$datestring] $@" | fold -w70 -s | sed '2~1s/^/  /' >&2
}

log_error() {
    log "ERROR: $1"
    exit $2
}

check_return_code() {
    if [ $1 -ne 0 ]
    then
        log "ERROR: $2 ($1)"
        exit $3
    fi
}

update_repos() {
    log Updating repos...

    # apt sources for yarn
    curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
    echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
    # needed to add repositories
    sudo apt install -y software-properties-common
    # repository for latest versions of php
    sudo add-apt-repository -y ppa:ondrej/php
    # repository for certbot (letsencrypt)
    sudo apt-add-repository ppa:certbot/certbot
    # update and upgrade
    sudo apt update && sudo apt upgrade -y
    # install en_US locale
    sudo locale-gen en_US
}

install_software() {
    log Installing Nginx...
    sudo apt install -y nginx
    check_return_code $? "Unable to install Nginx" $ERRCODE_APT_INSTALL

    log Installing PHP $PHP_VER...
    php="php$PHP_VER"
    sudo apt install -y $php $php-xml $php-gd $php-opcache $php-mbstring $php-cli $php-mysql $php-zip $php-curl
    check_return_code $? "Unable to install PHP $PHP_VER" $ERRCODE_APT_INSTALL
    php -v

    log Unistalling Apache...
    sudo apt-get purge -y apache2 apache2-utils apache2-bin apache2.2-common
    check_return_code $? "Unable to uninstall Apache" $ERRCODE_APT_INSTALL

    log Installing MySQL...
    sudo apt install -y mysql-server
    check_return_code $? "Unable to install MySQL" $ERRCODE_APT_INSTALL

    log Installing unzip and other stuff...
    sudo apt install -y unzip
    check_return_code $? "Unable to install remaining software" $ERRCODE_APT_INSTALL

    log Installing Composer...
    curl -sS https://getcomposer.org/installer -o composer-setup.php
    check_return_code $? "Unable to download Composer" $ERRCODE_APT_INSTALL
    sudo php composer-setup.php --install-dir=/usr/local/bin --filename=composer
    check_return_code $? "Unable to install Composer" $ERRCODE_APT_INSTALL
    rm composer-setup.php
    sudo chown -R ubuntu:ubuntu ~/.composer
    check_return_code $? "Unable to chown Composer" $ERRCODE_APT_INSTALL
    # speed up composer
    composer global require hirak/prestissimo

    log Installing Nodejs and Yarn...
    sudo apt install -y nodejs npm yarn
    check_return_code $? "Unable to install Nodejs and Yarn" $ERRCODE_APT_INSTALL

    log Installing certbot
    sudo apt install -y certbot
    check_return_code $? "Unable to install certbot" $ERRCODE_APT_INSTALL
    sudo apt install -y python3-pip
    check_return_code $? "Unable to install Python PIP" $ERRCODE_APT_INSTALL
    pip3 install certbot-dns-route53
    check_return_code $? "Unable to install certbot-dns-route53" $ERRCODE_APT_INSTALL

    log Cleaning apt cache...
    sudo apt autoremove -y
    sudo apt-get clean -y
    sudo apt-get autoclean -y
}

gen_nginx_config() {
    if [ $2 -eq 1 ]
    then
        default="default_server"
    else
        default=""
    fi

    echo "server { 
        listen 80 $default;
        listen [::]:80 $default;
        
        root /var/www/$1/public;
        index index.php index.html index.htm;
        server_name $1.$domain;
        
        location / {
            try_files \$uri \$uri/ /index.php?\$query_string;
        } 
        
        location ~ \\.php\$ {
            include snippets/fastcgi-php.conf;
            fastcgi_pass unix:/run/php/php7.3-fpm.sock;
        }
        
    }"
}

############################################################################
# load configuration
############################################################################

log STARTING: $0 $@

log "Loading configuration..."

. $CONFIG_FILE
check_return_code $? "Could not read $CONFIG_FILE" $ERRCODE_CONFIG_READ_FILE

if [ -z $environments ]
then
    log_error "Missing value environments" $ERRCODE_CONFIG_MISSING_ENVS
fi

if [ -z $domain ]
then
    log_error "Missing value domain" $ERRCODE_CONFIG_MISSING_ENVS
fi

update_repos

install_software

cp ./update.sh .. && chmod +x ../update.sh
check_return_code $? "Could not copy update.sh" $ERRCODE_COPY_UPDATE_SH

cp $CONFIG_FILE ..

cd ..

num_environ=0
for environ in ${environments[@]}
do
    num_environ=$(( num_environ + 1 ))

    log "Creating $environ ($num_environ/${#environments[@]})..."

    mkdir $environ
    cd $environ

    log Creating storage directory...
    mkdir -p storage/app/public
    mkdir -p storage/framework/cache/data
    mkdir -p storage/framework/sessions
    mkdir -p storage/framework/testing
    mkdir -p storage/framework/views
    mkdir -p storage/logs
    sudo chown -R www-data:www-data storage
    sudo chmod -R 777 storage

    log Creating first run website...
    web_dir=web_first_run
    mkdir -p $web_dir/public
    echo "This is the $environ server running!" | sudo tee $web_dir/public/index.html > /dev/null
    sudo chown -R www-data:www-data $web_dir
    sudo find $web_dir -type f -exec chmod 644 {} \;
    sudo find $web_dir -type d -exec chmod 755 {} \;

    log Linking /var/www/$environ to $(pwd)/$web_dir...
    sudo ln -sfn $(pwd)/$web_dir /var/www/$environ
    sudo chown -h www-data:www-data /var/www/$environ

    log Generating Nginx config file...
    gen_nginx_config $environ $num_environ > /tmp/tmp_nginx_config_$environ
    sudo mv /tmp/tmp_nginx_config_$environ /etc/nginx/sites-available/$environ
    sudo chown root:root /etc/nginx/sites-available/$environ

    log Enabling config file...
    sudo ln -sf /etc/nginx/sites-available/$environ /etc/nginx/sites-enabled/$environ

    cd ..
done

sudo mv /etc/nginx/sites-available/default /etc/nginx/sites-available/_default
sudo rm /etc/nginx/sites-enabled/default

sudo chown -R www-data:www-data /var/www
sudo chmod -R 755 /var/www

sudo service nginx restart

log Done!
echo ""
echo Do not forget to create the .env files for each environment.
