# Projeto DashboardMonitor

Projeto desenvolvido para a disciplina de **Sistemas Operacionais (SO)**.

## Objetivo do Projeto

Aplicar conceitos estudados na disciplina de **Sistemas Operacionais**, utilizando estruturas da linguagem Bash.

## Requisitos

1. O script precisa ter comentário em todas as estruturas;
2. Todas as variáveis do código precisam estar em maiúsculo;
3. Todo o código precisa estar indentado;
4. O código precisa prever um parâmetro `h` ou `help` para informar sobre o funcionamento do script;
5. O código precisa utilizar todas as estruturas trabalhadas na disciplina.

## Integrantes

* Cleyton Ferreira
* Hitaro Ramos

## Propósito

Desenvolver um script para **monitoramento e administração de servidores Linux**, permitindo acompanhar de forma centralizada informações sobre o sistema, recursos de hardware, armazenamento, rede, segurança, processos e serviços.

O DashboardMonitor foi desenvolvido com foco em **servidores**, auxiliando na identificação de possíveis problemas e na realização de tarefas de manutenção e gerenciamento do sistema.

## Tecnologias utilizadas

* **Bash** — Linguagem utilizada no desenvolvimento do script;
* **Linux** — Kernel que intermedia informações entre o sistema operacional e hardware.
* **File System** — Estrutura de arquivos e diretórios utilizada pelo sistema;
* **APT** — Gerenciador de pacotes;
* **Systemd** — Gerenciamento de serviços do sistema;
* **Journalctl** — Consulta aos logs do sistema;
* **Flatpak** — Gerenciamento de aplicações Flatpak;
* **Docker** — Gerenciamento e consulta de containers.

## Funcionalidades

O script possui as seguintes funcionalidades:

### Dashboard

Apresenta informações importantes do servidor em primeiro plano:

* Nome e versão do sistema operacional;
* Tempo de atividade do servidor;
* Nome da máquina;
* Data e hora;
* Uso de CPU;
* Uso de memória RAM;
* Uso de disco;
* Informações de rede;
* Conexões ativas;
* Portas em escuta;
* Usuários conectados;
* Status do UFW;
* Status do Fail2ban;
* Latência DNS;
* Espaço utilizado em `/tmp`;
* Espaço utilizado em `/var/log`;
* Conntrack do kernel;
* File Descriptors;
* Processos zumbis;
* Status dos principais serviços;
* Containers Docker;
* Processos que mais utilizam CPU e memória;
* Alertas de utilização dos recursos.

### Menu de administração

O sistema possui um menu com diferentes funções:

| Opção | Função                                                |
| ----- | ----------------------------------------------------- |
| 1     | Diagnóstico detalhado                                 |
| 2     | Consulta de logs críticos                             |
| 3     | Informações de rede e usuários                        |
| 4     | Verificação e instalação de atualizações de segurança |
| 5     | Listagem de pacotes APT instalados                    |
| 6     | Pesquisa e remoção de pacotes APT                     |
| 7     | Pesquisa e remoção de aplicações Flatpak              |
| 8     | Remoção de dependências obsoletas                     |
| 9     | Configuração dos limites de alerta                    |
| 0     | Encerramento do programa                              |

### Diagnóstico detalhado

Gera um relatório com informações de infraestrutura do servidor, incluindo:

* Sistema operacional e kernel;
* Arquitetura;
* Tempo de atividade;
* Shell;
* Pacotes instalados;
* Informações de rede;
* CPU;
* Memória RAM e SWAP;
* Armazenamento;
* Dispositivos de bloco;
* Sistemas de arquivos;
* Diretórios que mais ocupam espaço;
* Informações de segurança;
* Usuários conectados;
* Serviços do Systemd;
* Containers Docker;
* Processos que mais utilizam CPU e memória;
* Alertas do sistema.

O relatório pode ser exportado para um arquivo `.txt`.

### Monitoramento e alertas

O DashboardMonitor verifica os principais recursos do servidor e apresenta alertas quando os valores ultrapassam os limites configurados.

É possível configurar os limites de:

* CPU;
* Memória RAM;
* Disco.

### Gerenciamento de dependências

O script verifica algumas dependências necessárias para seu funcionamento e pode realizar a instalação delas utilizando o **APT**.

Entre as ferramentas verificadas estão:

* `column`;
* `mpstat`;
* `ufw`;
* `fail2ban-client`;
* `curl`;
* `dig`.

## Observação

O DashboardMonitor realiza operações administrativas no sistema, como instalação e remoção de pacotes, atualização de pacotes e gerenciamento de serviços. Por isso, sua execução requer privilégios de administrador (`sudo`).

## Como executar

O script deve ser executado com privilégios administrativos.

```bash
sudo ./DashboardMonitor.sh
```

Ao executar sem parâmetros, o sistema inicia o modo interativo com o dashboard e o menu de administração.

## Opções de inicialização

### Dashboard

Para exibir somente o resumo do servidor e encerrar:

```bash
sudo ./DashboardMonitor.sh -d
```

Também pode ser utilizado:

```bash
sudo ./DashboardMonitor.sh --dashboard
```

### Ajuda

Para visualizar as opções disponíveis:

```bash
sudo ./DashboardMonitor.sh -h
```

Também podem ser utilizados:

```bash
sudo ./DashboardMonitor.sh --help
```

ou:

```bash
sudo ./DashboardMonitor.sh help
```

## Estrutura do projeto

```text
DashboardMonitor/
├── DashboardMonitor.sh
├── config/
│   ├── alertas.conf
│   ├── dependencias.conf
│   └── servicos.conf
└── README.md
```

Os arquivos de configuração são criados automaticamente pelo script dentro do diretório `config/`, caso ainda não existam.
