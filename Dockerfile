FROM ipython/ipython

RUN mkdir -p /srv/

# install localhub
WORKDIR /srv/
ADD . /srv/localhub
WORKDIR /srv/localhub/localhubd
RUN npm install

# install localhub apps
RUN mkdir -p /srv/localapps

WORKDIR /srv/localapps
RUN git clone https://github.com/localhub/dashboard
WORKDIR /srv/localapps/dashboard
RUN ./setup

WORKDIR /srv/localapps
RUN git clone https://github.com/localhub/terminal
WORKDIR /srv/localapps/terminal
RUN ./setup

WORKDIR /srv/localhub/
EXPOSE 4000

CMD ["bin/localhubd", "/srv/localapps"]
