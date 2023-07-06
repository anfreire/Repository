# MINI SERV

## Header files

```c
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <stdio.h>
```

---

## Constants

```c
//--------------------------------------------------------
// Client states
#define UNUSED      -1
#define LEFT        -2
```

```c
//--------------------------------------------------------
// Server settings
#define MAX_CLIENTS 1024
#define BUFFER_SIZE 4096
```

```c
//--------------------------------------------------------
//  Error messages
#define ERR_ARGS    "Wrong number of arguments\n"
#define ERR_SYS     "Fatal error\n"
#define ERR_ALLOC   "Falal error\n"
```

```c
//--------------------------------------------------------
// Server messages
#define MSG_CNCT    "server: client %d just arrived\n"
#define MSG_LEFT    "server: client %d just left\n"
```

```c
//--------------------------------------------------------
// Client messages
#define MSG_CLIENT  "client %d: %s\n"
```

---

## Structures

```c
typedef struct client
{
    int socket;
    int id;
} client;
```
A struct to store a client's socket and id
- **param** *socket* The client's socket
- **param** *id* The client's id

&nbsp;

---

## Functions

```c
void broadcast(char *buffer, client *clients, int ignoreFd)
{
    for (int i = 0; i < MAX_CLIENTS; i++)
    {
        if (clients[i].socket != ignoreFd && clients[i].socket >= 0)
        {
            send(clients[i].socket, buffer, strlen(buffer), 0);
        }
    }
}
```
Sends a message to all clients except the one with the given socket
- **param** *buffer* The message to send
- **param** *clients* The array of clients
- *To send a message to all clients, set ignoreFd to a negative value*

&nbsp;
&nbsp;

```c
char *ft_realloc_1(char *str, int oldSize)
{
    str = realloc(str, sizeof(char) * (oldSize + 1));
    if (str == NULL)
    {
        write(STDERR_FILENO, ERR_ALLOC, strlen(ERR_ALLOC));
        exit(1);
    }
    str[oldSize] = 0;
    return str;
}
```
Reallocates a string to one character longer
- **param** *str* The string to reallocate
- **param** *oldSize* The old size of the string
- **return** The reallocated string

&nbsp;
&nbsp;

```c
char **ft_realloc_2(char **arr, int oldSize)
{
    arr = realloc(arr, sizeof(char *) * (oldSize + 1));
    if (arr == NULL)
    {
        write(STDERR_FILENO, ERR_ALLOC, strlen(ERR_ALLOC));
        exit(1);
    }
    arr[oldSize] = NULL;
    return arr;
}
```
Reallocates a array of strings to one string longer
- **param** *arr* The array of strings to reallocate
- **param** *oldSize* The old size of the array
- **return** The reallocated array
- *Prints an error message and exits if the reallocation fails*

&nbsp;
&nbsp;

```c
char **parseMsg(char *msg)
{
    char **parsedMsg = NULL;
    int i = 0;
    while(msg && *msg)
    {
        parsedMsg = ft_realloc_2(parsedMsg, i);
        int j = 0;
        while (msg[j] && msg[j] != '\n')
        {
            parsedMsg[i] = ft_realloc_1(parsedMsg[i], j);
            parsedMsg[i][j] = msg[j];
            j++;
        }
        parsedMsg[i] = ft_realloc_1(parsedMsg[i], j);
        if (msg[j] == '\n')
            j++;
        msg += j;
        i++;
    }
    parsedMsg = ft_realloc_2(parsedMsg, i);
    return parsedMsg;
}
```
Parses a message into an array of strings
- **param** *msg* The message to parse
- **return** The parsed message

&nbsp;
&nbsp;


```c
int getId(client *clients, int socket)
{
    for (int i = 0; i < MAX_CLIENTS; i++)
    {
        if (clients[i].socket == socket)
            return clients[i].id;
    }
    return -1;
}
```
Gets the id of a client with the given socket
- **param** *clients* The array of clients
- **param** *socket* The socket of the client 
- **return** The id of the client, or -1 if the client is not found

---

## Step-by-step

1.  Handle Wrong args
```c
    if (argc < 2)
    {
        write(STDERR_FILENO, ERR_ARGS, strlen(ERR_ARGS));
        exit(1);
    }
```

2.  Create and init the Client array
```c
    client clients[MAX_CLIENTS];
    for (int i = 0; i < MAX_CLIENTS; i++)
    {
        clients[i].socket = UNUSED;
        clients[i].id = UNUSED;
    }
```

3. Create the buffer, the serverAddres struct and the server socket. Set the serverAddress struct to the default values and try to create the server socket.
```c
    char buffer[BUFFER_SIZE];
    struct sockaddr_in serverAddress = {0};
    int serverSocket = socket(AF_INET, SOCK_STREAM, 0);
```

4. Check if the server socket is created
```c
    if (serverSocket < 0)
    {
        write(STDERR_FILENO, ERR_SYS, strlen(ERR_SYS));
        exit(1);
    }
```

5. Set the serverAddress struct and the max socket
```c
    serverAddress.sin_family = AF_INET;
    serverAddress.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    serverAddress.sin_port = htons(atoi(argv[1]));
    int maxSocket = serverSocket;
```

6. Try to bind the server socket to the serverAddress struct
```c
    if (bind(serverSocket, (struct sockaddr *)&serverAddress, sizeof(serverAddress)) < 0)
    {
        write(STDERR_FILENO, ERR_SYS, strlen(ERR_SYS));
        exit(1);
    }
```

7. Try to listen to the server socket
```c
    if (listen(serverSocket, MAX_CLIENTS) < 0)
    {
        write(STDERR_FILENO, ERR_SYS, strlen(ERR_SYS));
        exit(1);
    }
```

8. Create a set for the sockets and another one for the sockets that are ready to read
```c
    fd_set sockets, socketsReady;
    FD_ZERO(&sockets);
    FD_SET(serverSocket, &sockets);
```

9. Enter an infinite loop
```c
    while (1)
    {
```

10. Set the socketsReady set to the sockets set, because the select function will modify the socketsReady set
```c
        socketsReady = sockets;
```

11. Try to select the sockets that are ready to read. If the select function fails, print an error message and exit the program
```c
        if (select(maxSocket + 1, &socketsReady, NULL, NULL, NULL) < 0)
        {
            write(STDERR_FILENO, ERR_SYS, strlen(ERR_SYS));
            exit(1);
        }
```

12. Loop through all the sockets
```c
        for (int i = 0; i <= maxSocket; i++)
        {
```

13. Check if the current socket is in the socketsReady set
```c
            if (FD_ISSET(i, &socketsReady))
            {
```

14. Check if the current socket is the server socket. Because if it is, it means that a new client is trying to connect to the server
```c
                if (i == serverSocket)
                {
```

15. Accept the new client
```c
                    int clientSocket = accept(serverSocket, NULL, NULL);
```

16. Check if the accept function failed. If it did, print an error message and exit the program
```c
                    if (clientSocket < 0)
                    {
                        write(STDERR_FILENO, ERR_SYS, strlen(ERR_SYS));
                        exit(1);
                    }
```

17. Add the new client to the set of sockets and update the max socket
```c
                    FD_SET(clientSocket, &sockets);
                    if (clientSocket > maxSocket)
                        maxSocket = clientSocket;
```

18. Add the client to the client array
```c
                    for (int j = 0; j < MAX_CLIENTS; j++)
                    {
                        if (clients[j].socket == UNUSED)
                        {
                            clients[j].socket = clientSocket;
                            clients[j].id = j;
                            break;
                        }
                    }
```

19. Send to all the connected clients the message that a new client has connected
```c
                    sprintf(buffer, MSG_CNCT, getId(clients, clientSocket));
                    broadcast(buffer, clients, -1);
                }
```

20. If the current socket is not the server socket, it means that a client is trying to send a message to the server
```c
                else
                {
```

21. Create a buffer for the message and try to read the message from the client
```c
                    char msg[BUFFER_SIZE];
                    int readBytes = recv(i, msg, BUFFER_SIZE, 0);
```

22. Check if the recv function failed. If it did, print an error message and exit the program
```c
                    if (readBytes < 0)
                    {
                        write(STDERR_FILENO, ERR_SYS, strlen(ERR_SYS));
                        exit(1);
                    }
```

23. Check if the readBytes is 0. If it is, it means that the client has disconnected from the server
```c
                    if (readBytes == 0)
                    {
```

24. Send a message to all the connected clients that the client with the socketId has disconnected from the server, update the client array with LEFT macro so it will not be set again, close the socket and remove it from the set of sockets
```c
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
```

25. If the readBytes is not 0, it means that the client has sent a message to the server
```c
                    else
                    {
```

26. Make the buffer null terminated, parse the message and send it to all the connected clients, except the client that sent the message
```c
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
```

---

## Full Code

```c
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <stdlib.h>
#include <stdio.h>
#include <sys/select.h>

#define UNUSED      -1
#define LEFT        -2
#define MAX_CLIENTS 1024
#define BUFFER_SIZE 4096
#define ERR_ARGS    "Wrong number of arguments\n"
#define ERR_SYS     "Fatal error\n"
#define ERR_ALLOC   "Falal error\n"
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
        if (clients[i].socket != ignoreFd && clients[i].socket >= 0)
        {
            send(clients[i].socket, buffer, strlen(buffer), 0);
        }
    }
}

char *ft_realloc_1(char *str, int oldSize)
{
    str = realloc(str, sizeof(char) * (oldSize + 1));
    if (str == NULL)
    {
        write(STDERR_FILENO, ERR_ALLOC, strlen(ERR_ALLOC));
        exit(1);
    }
    str[oldSize] = 0;
    return str;
}

char **ft_realloc_2(char **str, int oldSize)
{
    str = realloc(str, sizeof(char *) * (oldSize + 1));
    if (str == NULL)
    {
        write(STDERR_FILENO, ERR_ALLOC, strlen(ERR_ALLOC));
        exit(1);
    }
    str[oldSize] = NULL;
    return str;
}

char **parseMsg(char *msg)
{
    char **parsedMsg = NULL;
    int i = 0;
    while(msg && *msg)
    {
        parsedMsg = ft_realloc_2(parsedMsg, i);
        int j = 0;
        while (msg[j] && msg[j] != '\n')
        {
            parsedMsg[i] = ft_realloc_1(parsedMsg[i], j);
            parsedMsg[i][j] = msg[j];
            j++;
        }
        parsedMsg[i] = ft_realloc_1(parsedMsg[i], j);
        if (msg[j] == '\n')
            j++;
        msg += j;
        i++;
    }
    parsedMsg = ft_realloc_2(parsedMsg, i);
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
        write(STDERR_FILENO, ERR_ARGS, strlen(ERR_ARGS));
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
    struct sockaddr_in serverAddress = {0};
    int serverSocket = socket(AF_INET, SOCK_STREAM, 0);

    if (serverSocket < 0) 
    {
        write(STDERR_FILENO, ERR_SYS, strlen(ERR_SYS));
        exit(1);
    }
    serverAddress.sin_family = AF_INET;
    serverAddress.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    serverAddress.sin_port = htons(atoi(argv[1]));
    if (bind(serverSocket, (struct sockaddr *)&serverAddress, sizeof(serverAddress)) < 0)
    {
        write(STDERR_FILENO, ERR_SYS, strlen(ERR_SYS));
        exit(1);
    }

    if (listen(serverSocket, MAX_CLIENTS) < 0) 
    {
        write(STDERR_FILENO, ERR_SYS, strlen(ERR_SYS));
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
            write(STDERR_FILENO, ERR_SYS, strlen(ERR_SYS));
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
                        write(STDERR_FILENO, ERR_SYS, strlen(ERR_SYS));
                        exit(1);
                    }
                    FD_SET(clientSocket, &activeSockets);
                    if (clientSocket > maxSocket)
                        maxSocket = clientSocket;
                    for (int i = 0; i < MAX_CLIENTS; i++)
                    {
                        if (clients[i].socket == UNUSED)
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
                    if (bytesRead < 0)
                    {
                        write(STDERR_FILENO, ERR_SYS, strlen(ERR_SYS));
                        exit(1);
                    }
                    if (bytesRead == 0)
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
```