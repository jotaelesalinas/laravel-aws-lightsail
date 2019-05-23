############################################################################
# constants
############################################################################

CONFIG_FILE=config.ini

# do not modify anything from now on!

ERRCODE_MISSING_ARGUMENT=1
ERRCODE_WRONG_ARGUMENT=2

ERRCODE_READ_CONFIG_FILE=3
ERRCODE_READ_CONFIG_VARS=4

ERRCODE_CD_TO_ENVIRONMENT=5

ERRCODE_GIT_CLONE=6
ERRCODE_GIT_COMMIT=7
ERRCODE_RENAME_REPO=8

ERRCODE_COMPOSER=9
ERRCODE_YARN=10

ERRCODE_COPY_ENV=11
ERRCODE_DELETE_STORAGE=12
ERRCODE_LINK_STORAGE=13
ERRCODE_LINK_PUBLIC_STORAGE=14

ERRCODE_CACHE_CONFIG=15
ERRCODE_CACHE_ROUTES=16
ERRCODE_MIGRATE=17

ERRCODE_CHOWN_REPO=18
ERRCODE_CHMOD_FILES=19
ERRCODE_CHMOD_DIRS=20
ERRCODE_CHMOD_BOOTSTRAP_CACHE=21

ERRCODE_NGINX_UNLINK=22
ERRCODE_NGINX_RELINK=23
ERRCODE_NGINX_CHOWN=24

ERRCODE_RESTART_NGINX=25
ERRCODE_RESTART_PHP=26
ERRCODE_RELOAD_PHP=27

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

usage() {
    log "ERROR: $1"
    echo "Possible values:"
    for environ in $(find /var/www -maxdepth 1 -type l -exec basename {} \;)
    do
        if [ -d ./$environ ]
        then
            echo "    -" $environ
        fi
    done
}

env_exists() {
    for environ in $(find /var/www -maxdepth 1 -type l -exec basename {} \;)
    do
        if [ $1 == $environ ]
        then
            echo 1
            return 0
        fi
    done
    echo 0
    return 1
}

check_return_code() {
    if [ $1 -ne 0 ]
    then
        log "ERROR: $2 ($1)"
        exit $3
    fi
}

############################################################################
# validate argument(s)
############################################################################

log STARTING: $0 $@

if [ -z "$1" ]
then
    usage "Missing environment."
    exit $ERRCODE_MISSING_ARGUMENT
fi

# possible improments:
# - check if $1 is a valid directory with / at the end
# - check if $1* is one directory and it is valid
environ=$1

if [ `env_exists $environ` -eq 0 ]
then
    usage "Wrong environment $environ."
    exit $ERRCODE_WRONG_ARGUMENT
fi

############################################################################
# load configuration
############################################################################

log "Loading configuration..."

source <(grep = $CONFIG_FILE | sed 's/ *= */=/g')
check_return_code $? "Could not read $CONFIG_FILE" $ERRCODE_READ_CONFIG_FILE

var_branch="git_branch_$environ"
if [ -z $var_branch ]; then
    log_error "Missing value $var_branch" $ERRCODE_READ_CONFIG_VARS
else
    git_branch=${!var_branch}
    #echo - $var_branch: $git_branch
    log "- git_branch: $git_branch"
fi

if [ -z $git_site ]; then
    log_error "Missing value var_branch" $ERRCODE_READ_CONFIG_VARS
else
    log "- git_site: $git_site"
fi

if [ -z $git_user ]; then
    log_error "Missing value git_user" $ERRCODE_READ_CONFIG_VARS
else
    log "- git_user: $git_user"
fi

if [ -z $git_repo ]; then
    log_error "Missing value git_repo" $ERRCODE_READ_CONFIG_VARS
else
    log "- git_repo: $git_repo"
fi

############################################################################
# start updating
############################################################################

log "Updating $environ..."

cd $environ
check_return_code $? "Could not change to directory $environ" $ERRCODE_CD_TO_ENVIRONMENT

dir_environ=`pwd`
log "- dir_environ: $dir_environ"

############################################################################
# clone from git
############################################################################

log "Cloning from git repository..."

git_dir=$git_repo-$(date --utc +%Y%m%d_%H%M%SZ)

git clone -b $git_branch git@$git_site:$git_user/$git_repo.git $git_dir
check_return_code $? "Error while running 'git clone'" $ERRCODE_GIT_CLONE

# change to cloned repo just to get commit id
log "Reading commit id..."
cd $git_dir
git_commit=$(git log --format="%H" -n 1 | cut -c-8)
if [ -z $git_commit ]
then
    log_error "Could not get commit of cloned repo" $ERRCODE_GIT_COMMIT
fi
cd ..

# rename repo dir adding the commit id
log "Renaming repo dir..."
new_name=$git_dir-$git_commit
mv $git_dir $new_name
check_return_code $? "Could not rename repo dir to append commit" $ERRCODE_RENAME_REPO

git_dir=$new_name
log "- git_dir: $git_dir"

############################################################################
# install and configure the laravel application
############################################################################

log "Installing the Laravel application..."

cd $git_dir

dir_laravel=`pwd`

log "Running composer..."
composer install --no-suggest
check_return_code $? "Error while running 'composer install'" $ERRCODE_COMPOSER

log "Running yarn..."
yarn install
check_return_code $? "Error while running 'yarn install'" $ERRCODE_YARN

log "Copying .env ..."
cp ../.env.$environ .env
check_return_code $? "Could not copy ../.env.$environ" $ERRCODE_COPY_ENV

# link storage so that data is not lost between updates
log "Linking storage..."
rm -r storage
check_return_code $? "Could not delete storage" $ERRCODE_DELETE_STORAGE
ln -s $dir_environ/storage storage
check_return_code $? "Could not link storage" $ERRCODE_LINK_STORAGE
php artisan storage:link
check_return_code $? "Could not link public/storage" $ERRCODE_LINK_PUBLIC_STORAGE

log "Laravel caching..."
# cache config
php artisan config:cache
check_return_code $? "Could not cache config" $ERRCODE_CACHE_CONFIG

# cache routes
# not compatible with auth at the moment
#php artisan route:cache
#check_return_code $? "Could not cache routes" $ERRCODE_CACHE_ROUTES

# auto migrate or not auto migrate, that is the question
log "Migrating database..."
php artisan migrate --force
check_return_code $? "Could not migrate database" $ERRCODE_MIGRATE

# go back to parent dir
cd ..

############################################################################
# reconfigure nginx
############################################################################

log "Reconfiguring Nginx..."

log "- git_dir: $git_dir"
log "- dir_laravel: $dir_laravel"
log "- environ: $environ"

log Changing ownership and permissions of repo...

sudo chown -R www-data:www-data $git_dir
check_return_code $? "Could not change ownership of repo" $ERRCODE_CHOWN_REPO

# files 644
sudo find $dir_laravel -type f -exec chmod 644 {} \;
check_return_code $? "Could not change permissions of files" $ERRCODE_CHMOD_FILES

# dirs 755
sudo find $dir_laravel -type d -exec chmod 755 {} \;
check_return_code $? "Could not change permissions of dirs" $ERRCODE_CHMOD_DIRS

sudo chmod -R 777 $git_dir/bootstrap/cache
check_return_code $? "Could not change permissions of bootstrap/cache" $ERRCODE_CHMOD_BOOTSTRAP_CACHE

log Relinking /var/www/$environ to repo...

sudo unlink /var/www/$environ       # -f is not working for some reason in the next line
check_return_code $? "Could not unlink /var/www/$environ" $ERRCODE_NGINX_UNLINK

sudo ln -sf $dir_laravel /var/www/$environ
check_return_code $? "Could not relink /var/www/$environ" $ERRCODE_NGINX_RELINK

sudo chown -h www-data:www-data /var/www/$environ
check_return_code $? "Could not change ownership of /var/www/$environ" $ERRCODE_NGINX_CHOWN

# delete compiled views
sudo rm storage/framework/views/*

log Restarting Nginx and PHP opcache...

sudo service nginx restart
check_return_code $? "Could not restart Nginx" $ERRCODE_RESTART_NGINX

sudo service php7.3-fpm reload
check_return_code $? "Could not reload PHP opcache" $ERRCODE_RELOAD_PHP

log SUCCESS!
