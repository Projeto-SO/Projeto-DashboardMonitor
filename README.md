# Projeto DashboardMonitor

Projeto desenvolvido para a disciplina de **Sistemas Operacionais (SO)**.

## Requisitos 

 1) O script precisa ter comentário em todas as estruturas;
 2) Todas as variáveis do código precisam estar em maiúsculo;
 3) Todo o código precisa estar indentado;
 4) O código precisa prever um parâmetro "h" ou "help" para informar sobre o funcionamento do script;
 5) O código precisa utilizar todas as estruturas trabalhadas na disciplina.

## Integrantes

 - Cleyton Ferreira
 - Hitaro Ramos

## Propósito 

Desenvolver um script que converse com o sistema operacional Linux e o gerenciador de pacotes apt. Para ajudar um usuário iniciante ter mais controle sobre sua máquina e posteriormente mais segurança.

## Tecnologias utilizadas

 - Bash -- Linguagem de programação utilizada no desenvolvimento;
 - Linux -- Kernel que realiza a comunicação entre o hardware e o sistema operacional;
 - File System -- Estrutura de diretórios;
 - APT -- Gerenciador de pacotes.

## Funcionalidades
O script possui as seguintes funcionalidades:

 ### Visualização em primeiro plano
 - Informações do sistema(Nome e versão do Sistema operacional, tempo ligado, nome da máquina, data);
 - Uso de CPU, MEMÓRIA, DISCO;
 - Maiores diretórios que usam disco ou ram;
 - Status dos serviços ssh, ufw, cron, docker, ngix, networking, apache2;
 - Recursos da máquina especificos como Latência DNS, Espaço /tmp, Conntrack (Kernel), Espaço /var/log, Arquivos/FDs,  Proc. Zumbis;

 ### Menu com especialidades
 - Diagnóstico       Gera relatório completo de infraestrutura e exporta em TXT;
 - Logs Críticos     Exibe erros recentes do sistema via journalctl;
 - Redes e Usuários  Apresenta sockets, portas em escuta e acessos no sistema;
 - Atualizações      Verifica e instala atualizações de segurança pendentes;
 - Listar Pacotes    Lista todos os pacotes APT instalados no sistema;
 - Gestão APT        Procura e remove pacotes/aplicações via APT;
 - Gestão Flatpak    Procura e remove aplicações instaladas via Flatpak;
 - Limpar Órfãos     Remove dependências obsoletas (apt autoremove);
 - Configurações     Ajusta os limites de alerta (CPU, RAM e Disco).


## Opções de inicialização do script

   -d, --dashboard    Exibe apenas o resumo (Dashboard) do sistema e encerra.
   -h, --help, help   Exibe este menu de ajuda detalhado e encerra.

   ´´´sudo ./DashboardMonitor.sh -d´´´
   ´´´sudo ./DashboardMonitor.sh -h´´´
   
