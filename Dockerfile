FROM centos:centos8.3.2011
ADD seamless-static-route.sh /usr/src/seamless-static-route
RUN chmod +x /usr/src/seamless-static-route