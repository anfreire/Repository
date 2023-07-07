#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <netdb.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <sys/select.h>
#include <sys/time.h>

#define MAX_CLIENTS 10
#define BUFFER_SIZE 40
#define ERR_ARGS    "Wrong number of arguments\n"
#define ERR_SYS     "Fatal error\n"
#define ERR_ALLOC   "Fatal error\n"
#define UNUSED      -2
#define LEFT        -1
#define LOG_CNCT    "server: client %d just arrived\n"
#define LOG_DSCNT  "server: client %d just left\n"
#define MSG_CLIENT_1 "client "
#define MSG_CLIENT_2 ": "

typedef struct client
{
    int fd;
    char *buffer;
} client;

void error(char *type)
{
    write(STDERR_FILENO, type, strlen(type));
    exit(1);
}

void    broadcast(char *msg, client *clients, int ignoreSocket)
{
    for (int i = 0; i < MAX_CLIENTS; i++)
    {
        if (clients[i].fd >= 0 && clients[i].fd != ignoreSocket)
            send(clients[i].fd, msg, strlen(msg), 0);
    }
}

int getId(client *clients, int socket)
{
    for (int i = 0; i < MAX_CLIENTS; i++)
    {
        if (clients[i].fd == socket)
            return i;
    }
    return -1;
}

int extract_message(char **buf, char **msg)
{
	char	*newbuf;
	int	i;

	*msg = 0;
	if (*buf == 0)
		return (0);
	i = 0;
	while ((*buf)[i])
	{
		if ((*buf)[i] == '\n')
		{
			newbuf = calloc(1, sizeof(*newbuf) * (strlen(*buf + i + 1) + 1));
			if (newbuf == 0)
				return (-1);
			strcpy(newbuf, *buf + i + 1);
			*msg = *buf;
			(*msg)[i + 1] = 0;
			*buf = newbuf;
			return (1);
		}
		i++;
	}
	return (0);
}

char *str_join(char *buf, char *add, int freeBuf)
{
	char	*newbuf;
	int		len;

	if (buf == 0)
		len = 0;
	else
		len = strlen(buf);
	newbuf = malloc(sizeof(*newbuf) * (len + strlen(add) + 1));
	if (newbuf == 0)
		return (0);
	newbuf[0] = 0;
	if (buf != 0)
		strcat(newbuf, buf);
    if (freeBuf)
	    free(buf);
	strcat(newbuf, add);
	return (newbuf);
}

void    handleMsg(client *clients, client *this)
{
    char *msg = NULL;
    if (this->buffer == NULL)
        return ;
    int ret = extract_message(&this->buffer, &msg);
    if (ret < 0)
        error(ERR_ALLOC);
    char id[10];
    sprintf(id, "%d", getId(clients, this->fd));
    while (ret == 1)
    {
        char *finalMsg = str_join(MSG_CLIENT_1, id, 0);
        finalMsg = str_join(finalMsg, MSG_CLIENT_2, 1);
        finalMsg = str_join(finalMsg, msg, 1);
        broadcast(finalMsg, clients, this->fd);
        free(finalMsg);
        free(msg);
        ret = extract_message(&this->buffer, &msg);
        if (ret < 0)
            error(ERR_ALLOC);
    }
    if (this->buffer && strlen(this->buffer) == 0)
    {
        free(this->buffer);
        this->buffer = NULL;
    }
}

int main(int ac, char **av)
{
    if (ac < 2)
        error(ERR_ARGS);
    char buffer[BUFFER_SIZE];
    int serverSocket;
    client  clients[MAX_CLIENTS];
    for (int i = 0; i < MAX_CLIENTS; i++)
    {
        clients[i].fd = UNUSED;
        clients[i].buffer = NULL;
    }
    struct sockaddr_in serverAddress = {0};
    serverSocket = socket(AF_INET, SOCK_STREAM, 0);
    if (serverSocket < 0)
        error(ERR_SYS);
    serverAddress.sin_family = AF_INET; 
	serverAddress.sin_addr.s_addr = htonl(2130706433);
	serverAddress.sin_port = htons(atoi(av[1]));
    if (bind(serverSocket, (struct sockaddr *)&serverAddress, sizeof(serverAddress)) < 0)
        error(ERR_SYS);
    if (listen(serverSocket, MAX_CLIENTS) < 0)
        error(ERR_SYS);
    int maxSocket = serverSocket;
    fd_set tmp_sockets, sockets;
    FD_ZERO(&sockets);
    FD_SET(serverSocket, &sockets);
    while (1)
    {
        tmp_sockets = sockets;
        if (select(maxSocket + 1, &tmp_sockets, NULL, NULL, NULL) < 0)
            error(ERR_SYS);
        for (int clientSocket = 0; clientSocket < MAX_CLIENTS; clientSocket++)
        {
            if (FD_ISSET(clientSocket, &tmp_sockets))
            {
                if (clientSocket == serverSocket)
                {
                    int newClient = accept(clientSocket, NULL, NULL);
                    if (newClient < 0)
                        error(ERR_SYS);
                    if (newClient > maxSocket)
                        maxSocket = newClient;
                    FD_SET(newClient, &sockets);
                    for (int i = 0; i < MAX_CLIENTS; i++)
                    {
                        if (clients[i].fd == UNUSED)
                        {
                            clients[i].fd = newClient;
                            memset(buffer, 0, BUFFER_SIZE);
                            sprintf(buffer, LOG_CNCT, i);
                            broadcast(buffer, clients, newClient);
                            break;
                        }
                    }
                }
                else
                {
                    char msg[BUFFER_SIZE + 1];
                    memset(msg, 0, BUFFER_SIZE + 1);
                    int readBytes = recv(clientSocket, msg, BUFFER_SIZE, 0);
                    if (readBytes < 0)
                        error(ERR_SYS);
                    if (readBytes == 0)
                    {
                        for (int i = 0; i < MAX_CLIENTS; i++)
                        {
                            if (clients[i].fd == clientSocket)
                            {
                                if (clients[i].buffer)
                                    handleMsg(clients, &clients[i]);
                                if (clients[i].buffer)
                                    free(clients[i].buffer);
                                memset(buffer, 0, BUFFER_SIZE);
                                sprintf(buffer, LOG_DSCNT, i);
                                broadcast(buffer, clients, clientSocket);
                                clients[i].fd = LEFT;
                                break;
                            }
                        }
                        FD_CLR(clientSocket, &sockets);
                        close(clientSocket);
                    }
                    else
                    {
                        msg[readBytes] = 0;
                        int allocatedBuf = 0;
                        if (clients[getId(clients, clientSocket)].buffer)
                            allocatedBuf = 1;
                        clients[getId(clients, clientSocket)].buffer = str_join(clients[getId(clients, clientSocket)].buffer, msg, allocatedBuf);
                    }
                }
            }
            if (clients[getId(clients, clientSocket)].fd >= 0 && getId(clients, clientSocket) >= 0)
                handleMsg(clients, &clients[getId(clients, clientSocket)]);
        }
    }
    return 0;
}