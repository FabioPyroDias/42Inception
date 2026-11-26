DATA_DIR = /home/fda-cruz/data
COMPOSE = docker-compose -f srcs/docker-compose.yml

all:
	mkdir -p $(DATA_DIR)/wordpress
	mkdir -p $(DATA_DIR)/mariadb
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

stop:
	$(COMPOSE) stop

start:
	$(COMPOSE) start

clean:
	$(COMPOSE) down --rmi all

fclean:
	$(COMPOSE) down --rmi all --volumes
	rm -rf $(DATA_DIR)/wordpress
	rm -rf &(DATA_DIR)/mariadb

re: fclean all 