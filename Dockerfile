FROM    ubuntu:latest


RUN	apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 7F0CEB10
RUN	echo 'deb http://downloads-distro.mongodb.org/repo/ubuntu-upstart dist 10gen' | tee /etc/apt/sources.list.d/mongodb.list
RUN	dpkg-divert --local --rename --add /sbin/initctl
RUN	ln -s /bin/true /sbin/initctl
RUN	apt-get update
RUN	apt-get install mongodb-10gen
RUN	mkdir -p /data/db

RUN apt-get update
RUN apt-get install -y python-software-properties python python-setuptools ruby rubygems
RUN add-apt-repository ppa:chris-lea/node.js

# Fixing broken dependencies ("nodejs : Depends: rlwrap but it is not installable"):
RUN echo "deb http://archive.ubuntu.com/ubuntu precise universe" >> /etc/apt/sources.list

RUN echo "deb http://us.archive.ubuntu.com/ubuntu/ precise universe" >> /etc/apt/sources.list
RUN apt-get update
RUN apt-get install -y nodejs 

# Removed unnecessary packages
RUN apt-get purge -y python-software-properties python python-setuptools ruby rubygems
RUN apt-get autoremove -y

# Clear package repository cache
RUN apt-get clean all

RUN npm install express mongoskin socket.io underscore node-uuid
RUN npm install -g coffee-script
