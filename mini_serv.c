#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <stdio.h>
#include <sys/select.h>

#define UNUSED      -1
#define LEFT        -2
#define MAX_CLIENTS 1000
#define BUFFER_SIZE 4096
#define ERR_ARGS    "Wrong number of arguments\n"
#define ERR_SYS     "Fatal error\n"
#define MSG_CNCT    "server: client %d just arrived\n"
#define MSG_LEFT    "server: client %d just left\n"
#define MSG_CLIENT  "client %d: %s\n"

typedef struct client
{
    int socket;
    int id;
} client;

void broadcast(char *buffer, client *clients, int ignoreFd)
{
    for (int i = 0; i < MAX_CLIENTS; i++)
    {
        if (clients[i].socket != ignoreFd && clients[i].socket != UNUSED && clients[i].id != LEFT)
        {
            send(clients[i].socket, buffer, strlen(buffer), 0);
        }
    }
}

char **parseMsg(char *msg)
{
    char **parsedMsg = NULL;
    int i = 0;
    while (msg && *msg)
    {
        parsedMsg = realloc(parsedMsg, sizeof(char *) * (i + 1));
        parsedMsg[i] = NULL;
        int j = 0;
        while (msg[j] && msg[j] != '\n')
        {
            parsedMsg[i] = realloc(parsedMsg[i], sizeof(char) * (j + 1));
            parsedMsg[i][j] = msg[j];
            j++;
        }
        parsedMsg[i] = realloc(parsedMsg[i], sizeof(char) * (j + 1));
        parsedMsg[i][j] = '\0';
        if (msg[j] == '\n')
            j++;
        msg += j;
        i++;
    }
    parsedMsg = realloc(parsedMsg, sizeof(char *) * (i + 1));
    parsedMsg[i] = NULL;
    return parsedMsg;
}

int getId(client *clients, int socket)
{
    for (int i = 0; i < MAX_CLIENTS; i++)
    {
        if (clients[i].socket == socket)
            return clients[i].id;
    }
    return -1;
}

int main(int argc, char **argv) 
{
    if (argc != 2) 
    {
        write(2, ERR_ARGS, strlen(ERR_ARGS));
        exit(1);
    }
    client clients[MAX_CLIENTS];
    for (int i = 0; i < MAX_CLIENTS; i++)
    {
        clients[i].socket = UNUSED;
        clients[i].id = UNUSED;
    }
    fd_set activeSockets, readySockets;
    char buffer[BUFFER_SIZE];
    int serverSocket = socket(AF_INET, SOCK_STREAM, 0);

    if (serverSocket < 0) 
    {
        write(2, ERR_SYS, strlen(ERR_SYS));
        exit(1);
    }

    struct sockaddr_in serverAddress = {0};
    serverAddress.sin_family = AF_INET;
    serverAddress.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    serverAddress.sin_port = htons(atoi(argv[1]));

    if (bind(serverSocket, (struct sockaddr *)&serverAddress, sizeof(serverAddress)) < 0) 
    {
        write(2, ERR_SYS, strlen(ERR_SYS));
        exit(1);
    }

    if (listen(serverSocket, MAX_CLIENTS) < 0) 
    {
        write(2, ERR_SYS, strlen(ERR_SYS));
        exit(1);
    }

    FD_ZERO(&activeSockets);
    FD_SET(serverSocket, &activeSockets);
    int maxSocket = serverSocket;
    while (1) 
    {
        readySockets = activeSockets;
        if (select(maxSocket + 1, &readySockets, NULL, NULL, NULL) < 0) 
        {
            perror("Error in select");
            exit(1);
        }

        for (int socketId = 0; socketId <= maxSocket; socketId++) 
        {
            if (FD_ISSET(socketId, &readySockets)) 
            {
                if (socketId == serverSocket) 
                {
                    int clientSocket = accept(serverSocket, NULL, NULL);
                    if (clientSocket < 0) 
                    {
                        perror("Error accepting client connection");
                        exit(1);
                    }

                    FD_SET(clientSocket, &activeSockets);
                    maxSocket = (clientSocket > maxSocket) ? clientSocket : maxSocket;
                    for (int i = 0; i < MAX_CLIENTS; i++)
                    {
                        if (clients[i].socket == -1)
                        {
                            clients[i].socket = clientSocket;
                            clients[i].id = i;
                            break;
                        }
                    }
                    sprintf(buffer, MSG_CNCT, getId(clients, clientSocket));
                    broadcast(buffer, clients, -1);
                } 
                else 
                {
                    char    msg[BUFFER_SIZE];
                    int bytesRead = recv(socketId, msg, BUFFER_SIZE, 0);
                    if (bytesRead <= 0) 
                    {
                        for (int i = 0; i < MAX_CLIENTS; i++)
                        {
                            if (clients[i].socket == socketId)
                            {
                                sprintf(msg, MSG_LEFT, clients[i].id);
                                broadcast(msg, clients, socketId);
                                clients[i].socket = LEFT;
                                clients[i].id = LEFT;
                                break;
                            }
                        }
                        close(socketId);
                        FD_CLR(socketId, &activeSockets);
                    } 
                    else 
                    {
                        msg[bytesRead] = '\0';
                        char **parsedMsg = parseMsg(msg);
                        for (int i = 0; parsedMsg[i]; i++)
                        {
                            sprintf(msg, MSG_CLIENT, getId(clients, socketId), parsedMsg[i]);
                            broadcast(msg, clients, socketId);
                        }
                        for (int i = 0; parsedMsg[i]; i++)
                            free(parsedMsg[i]);
                        free(parsedMsg);
                    }
                }
            }
        }
    }
    return 0;
}
