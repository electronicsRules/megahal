package MegaHAL::Shell;
use Text::ParseWords;

=pod

msg --server=highway-all --plugin=PMSyndicate #channel message does not require quotes

commands as hash structures:
#pseudostruct, DO NOT COPY!

    {# Permissions: *.*, *@highway-all.*, PMSyndicate@highway-all.*, _plugin@highway-all.*, PMSyndicate@highway-all.msg, PMSyndicate@*.*, _plugin@*.*, PMSyndicate@*.msg
        name: ['msg'],
        args: ['cserver','target','string+'],
        source: {'server': 'highway-all', 'plugin': 'PMSyndicate'},
    }
    {
        name: ['server','srv'],
        args: ['server'],
        sub: [
            {# Permissions: *.*, core@*.server.*, core@*.server.set, core@highway-all.*, core@*.*, *@highway-all.*, *@highway-all.server.*, *@highway-all.server.set
                name: ['set'],
                args: ['string','string'],
            },
            {# Permissions: *.*, core@*.server.delete, core@*.*
                name: ['delete','del'],
                confirm: 1     #Maybe.
                explicitacl: 1 #Requires explicit permission in the ACL - core@*.server.* is not good enough!
                noserveracl: 1 #All-server permissions required to do stuff - core@highway-all.delete is not good enough!
            }
        ]
    }
    {
        name: ['server','srv'], #also allows for plugins to extend existing top-level commands. not sure how to output help from this.
        args: ['string'],
        sub: [
            {# Permissions: *.*, core@*.server.*, core@*.server.add - since 'server' is not in typed-args, @<server> permissions are not an option.
                name: ['add','new'],
                opts: {
                    'address|ip=s',
                    'port=s',
                    'nick|nickname=s',
                    'user|username=s',
                    'real|gecos|realname=s'
                }
            }
        ]
    }

=cut