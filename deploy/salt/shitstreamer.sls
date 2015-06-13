{% set user = 'shitstream' %}

shitstream:
  user.present:
    - shell: /bin/bash
    - home: /home/shitstream

# Database
database:
  postgres_database.present:
    - name: {{ user }}
    - require:
      - pkg: packages
  postgres_user.present:
    - name: {{ user }}
    - password: password
    - superuser: True

alembic:
  cmd.run:
    - user: {{ user }}
    - name: ../../bin/python manage.py db upgrade
    - cwd: /var/www/shitstream/project/site/
    - require:
      - git: git-shitstream
      - virtualenv: /var/www/shitstream

# nginx
nginx-src:
  cmd.run:
    - name: apt-get source nginx=1.4.6
    - creates: /usr/src/nginx-1.4.6/
    - cwd: /usr/src/

nginx-rtmp-module-src:
  git.latest:
    - name: https://github.com/arut/nginx-rtmp-module.git
    - rev: v1.1.7
    - target: /usr/src/nginx-rtmp-module/
    - unless: test -d /usr/src/nginx-rtmp-module/

nginx-debian-rules:
  file.blockreplace:
    - name: /usr/src/nginx-1.4.6/debian/rules
    - marker_start: '--add-module=$(MODULESDIR)/ngx_http_substitutions_filter_module \'
    - content: '            --add-module=/usr/src/nginx-rtmp-module/ \'
    - marker_end: '>$@'
    - require:
      - cmd: nginx-src

nginx-build-dep:
  cmd.run:
    - name: apt-get -y build-dep nginx && touch /root/builddeps
    - creates: /root/builddeps

nginx-build-pkg:
  cmd.run:
    - name: dpkg-buildpackage -b
    - cwd: /usr/src/nginx-1.4.6/
    - output_loglevel: info
    - creates: /usr/src/nginx-full_1.4.6-1ubuntu3.2_amd64.deb
    - require:
      - git: nginx-rtmp-module-src
      - cmd: nginx-src
      - file: nginx-debian-rules
      - cmd: nginx-build-dep

nginx-install-pkg:
  pkg.installed:
    - sources:
      - nginx-common: /usr/src/nginx-common_1.4.6-1ubuntu3.2_all.deb
      - nginx-full: /usr/src/nginx-full_1.4.6-1ubuntu3.2_amd64.deb
    - require:
      - cmd: nginx-build-pkg

nginx-site:
  file.managed:
    - name: /etc/nginx/sites-enabled/shitstream
    - source: salt://config/nginx-shitstream
    - require:
      - pkg: nginx-install-pkg

nginx-cfg:
  file.blockreplace:
    - name: /etc/nginx/nginx.conf
    - marker_start: '# RTMP config -- start'
    - marker_end: '# RTMP config -- end'
    - content: |
            rtmp {
                    server {
                            listen 1935;
                            chunk_size 4000;
                            application stream { live on; }
                    }
            }
    - append_if_not_found: True
    - require:
      - pkg: nginx-install-pkg

rtmp-stats:
  file.copy:
    - name: /var/www/stat.xsl
    - source: /usr/src/nginx-rtmp-module/stat.xsl
    - makedirs: True
    - require:
      - git: nginx-rtmp-module-src

nginx-service:
  service.running:
    - name: nginx
    - watch:
      - file: nginx-cfg
      - file: nginx-site

# Gunicorn
/etc/init/gunicorn.conf:
  file.managed:
    - source: salt://config/gunicorn.conf
    - template: jinja
    - context:
    - user: {{ user }}

/var/log/gunicorn.log:
  file.managed:
    - user: {{ user }}

gunicorn:
  service:
    - running
    - require:
      - pkg: packages
      - file: /etc/init/gunicorn.conf
      - file: /var/log/gunicorn.log

# Producer/Veejay
/etc/init/producer.conf:
  file.managed:
    - source: salt://config/producer.conf
    - template: jinja
    - context:
    - user: {{ user }}

/var/log/producer.log:
  file.managed:
    - user: {{ user }}

producer:
  service:
    - running
    - require:
      - pkg: packages
      - cmd: alembic
      - file: /etc/init/producer.conf
      - file: /var/log/producer.log

/etc/init/veejay.conf:
  file.managed:
    - source: salt://config/veejay.conf
    - template: jinja
    - context:
    - user: {{ user }}

/var/log/veejay.log:
  file.managed:
    - user: {{ user }}

veejay:
  service:
    - running
    - require:
      - pkg: packages
      - cmd: alembic
      - file: /etc/init/veejay.conf
      - file: /var/log/veejay.log

github.com:
  ssh_known_hosts:
    - present
    - fingerprint: 16:27:ac:a5:76:28:2d:36:63:1b:56:4d:eb:df:a6:48

# Code/Virtualenv/Config
/var/www/shitstream:
  file.directory:
    - user: {{ user }}
    - makedirs: True
  virtualenv.managed:
    - user: {{ user }}
    - system_site_packages: False
    - requirements: /var/www/shitstream/project/site/requirements.txt
    - require:
      - git: git-shitstream
      - pip: python-pkgs

/etc/sudoers.d/ssh-agent:
  file.managed:
    - source: salt://config/sudo-ssh-agent
    - mode: 440

git-shitstream:
  git.latest:
    - user: {{ user }}
    - name: git@github.com:nijotz/shitstream.tv.git
    - target: /var/www/shitstream/project
    - rev: master
    - unless: test -d /var/www/shitstream/project
    - require:
      - pkg: packages
      - ssh_known_hosts: github.com
      - file: /etc/sudoers.d/ssh-agent
      - file: /var/www/shitstream

python-pkgs:
  pip.installed:
    - names:
      - virtualenv
      - requests >= 1.0.0
    - require:
      - pkg: packages

/var/www/shitstream/project/site/config.py:
  file.managed:
    - source: salt://config/config.py
    - require:
      - git: git-shitstream

packages:
  pkg.installed:
    - pkgs:
      - dpkg-dev
      - git
      - libpq-dev
      - postgresql
      - python-dev
      - python-pip
      - tmux
      - toilet
      - vim-nox
      - autoconf
      - automake
      - build-essential
      - libass-dev
      - libfreetype6-dev
      - libgpac-dev
      - libsdl1.2-dev
      - libtheora-dev
      - libtool
      - libva-dev
      - libvdpau-dev
      - libvorbis-dev
      - libxcb1-dev
      - libxcb-shm0-dev
      - libxcb-xfixes0-dev
      - pkg-config
      - texi2html
      - zlib1g-dev
      - yasm
      - libx264-dev
      - libmp3lame-dev
      - libopus-dev


ffmpeg-src:
  cmd.run:
    - name: wget http://ffmpeg.org/releases/ffmpeg-2.2.14.tar.bz2; tar xjvf ffmpeg-2.2.14.tar.bz2
    - cwd: /usr/src/
    - creates: /usr/src/ffmpeg-2.2.14/

ffmpeg-install:
  cmd.run:
    - name: ./configure --prefix="$HOME/ffmpeg_build" --extra-cflags="-I$HOME/ffmpeg_build/include" --extra-ldflags="-L$HOME/ffmpeg_build/lib"  --bindir="/usr/local/bin"  --enable-gpl  --enable-libass  --enable-libfreetype  --enable-libmp3lame  --enable-libopus  --enable-libtheora  --enable-libvorbis  --enable-libx264  --enable-nonfree; make; make install
    - cwd: /usr/src/ffmpeg-2.2.14
    - creates: /usr/local/bin/ffmpeg
    - require:
      - cmd: ffmpeg-src
