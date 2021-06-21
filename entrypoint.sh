#!/bin/sh

[ -z "${MQ_USER}" ] && echo 'Environment variable MQ_USER is empty' 1>&2 && exit 1
[ -z "${MQ_PASSWORD_HASH}" ] && echo 'Environment variable MQ_PASSWORD_HASH is empty' 1>&2 && exit 1

if [ -z "${MQ_SERVER_CERT}" ] || [ -z "${MQ_SERVER_KEY}" ]; then
SSL_SUBJ="/C=SE/ST=Sweden/L=Uppsala/O=NBIS/OU=SysDevs/CN=LocalEGA"
mkdir -p "/var/lib/rabbitmq/ssl"
# Generating the SSL certificate + key
openssl req -x509 -newkey rsa:2048 \
    -keyout "/var/lib/rabbitmq/ssl/mq-server.key" -nodes \
    -out "/var/lib/rabbitmq/ssl/mq-server.pem" -sha256 \
    -days 1000 -subj "${SSL_SUBJ}" && \
    chmod 600 /var/lib/rabbitmq/ssl/mq-server.*
fi


cat >> "/var/lib/rabbitmq/rabbitmq.conf" <<EOF
cluster_formation.peer_discovery_backend  = rabbit_peer_discovery_k8s
cluster_formation.k8s.host = kubernetes.default.svc.cluster.local
cluster_formation.k8s.address_type = hostname
cluster_formation.node_cleanup.interval = 10
cluster_partition_handling = autoheal
listeners.ssl.default = 5671
ssl_options.cacertfile = ${MQ_CA:-/etc/ssl/certs/ca-certificates.crt}
ssl_options.certfile = ${MQ_SERVER_CERT:-/var/lib/rabbitmq/ssl/mq-server.pem}
ssl_options.keyfile = ${MQ_SERVER_KEY:-/var/lib/rabbitmq/ssl/mq-server.key}
ssl_options.verify = ${MQ_VERIFY:-verify_peer}
ssl_options.fail_if_no_peer_cert = true
ssl_options.versions.1 = tlsv1.2
disk_free_limit.absolute = 1GB
management.listener.port = 15672
management.load_definitions = /var/lib/rabbitmq/definitions.json
default_vhost = ${MQ_VHOST:-/}
EOF

chmod 600 "/var/lib/rabbitmq/rabbitmq.conf"

if [ -n "${CEGA_CONNECTION}" ]; then
cat > "/var/lib/rabbitmq/definitions.json" <<EOF
{
  "users": [
    {
      "name": "${MQ_USER}",
      "password_hash": "${MQ_PASSWORD_HASH}",
      "hashing_algorithm": "rabbit_password_hashing_sha256",
      "tags": "administrator"
    }
  ],
  "vhosts": [
    {
      "name": "${MQ_VHOST:-/}"
    },
    {
      "name": "vm"
    }
  ],
  "permissions": [
    {
      "user": "${MQ_USER}",
      "vhost": "${MQ_VHOST:-/}",
      "configure": ".*",
      "write": ".*",
      "read": ".*"
    },
    {
      "user": "${MQ_USER}",
      "vhost": "vm",
      "configure": ".*",
      "write": ".*",
      "read": ".*"
    }
  ],
  "topic_permissions": [],
  "parameters": [
    {
      "name": "CEGA-files",
      "vhost": "${MQ_VHOST:-/}",
      "component": "federation-upstream",
      "value": {
        "ack-mode": "on-confirm",
        "queue": "v1.files",
        "trust-user-id": false,
        "uri": "${CEGA_CONNECTION}"
      }
    }
  ],
  "policies": [
    {
      "vhost": "${MQ_VHOST:-/}",
      "name": "CEGA-files",
      "pattern": "files",
      "apply-to": "queues",
      "priority": 0,
      "definition": {
        "federation-upstream": "CEGA-files",
        "ha-mode": "all",
        "ha-sync-mode": "automatic",
        "ha-sync-batch-size": 1
      }
    },
    {
      "name": "ha-vm",
      "pattern": ".*",
      "vhost": "vm",
      "definition": {
        "ha-mode": "all",
        "ha-sync-mode": "automatic",
        "ha-sync-batch-size": 1
      }
    }
  ],
  "queues": [
    {
      "name": "archived",
      "vhost": "${MQ_VHOST:-/}",
      "durable": true,
      "auto_delete": false,
      "arguments": {}
    },
    {
      "name": "backup",
      "vhost": "${MQ_VHOST:-/}",
      "durable": true,
      "auto_delete": false,
      "arguments": {}
    },
    {
      "name": "completed",
      "vhost": "${MQ_VHOST:-/}",
      "durable": true,
      "auto_delete": false,
      "arguments": {}
    },
    {
      "name": "files",
      "vhost": "${MQ_VHOST:-/}",
      "durable": true,
      "auto_delete": false,
      "arguments": {}
    },
    {
      "name": "inbox",
      "vhost": "${MQ_VHOST:-/}",
      "durable": true,
      "auto_delete": false,
      "arguments": {}
    },
    {
      "name": "ingest",
      "vhost": "${MQ_VHOST:-/}",
      "durable": true,
      "auto_delete": false,
      "arguments": {}
    },
    {
      "name": "mappings",
      "vhost": "${MQ_VHOST:-/}",
      "durable": true,
      "auto_delete": false,
      "arguments": {}
    },
    {
      "name": "accessionIDs",
      "vhost": "${MQ_VHOST:-/}",
      "durable": true,
      "auto_delete": false,
      "arguments": {}
    },
    {
      "name": "verified",
      "vhost": "${MQ_VHOST:-/}",
      "durable": true,
      "auto_delete": false,
      "arguments": {}
    },
    {
      "name": "manager",
      "vhost": "vm",
      "durable": true,
      "auto_delete": false,
      "arguments": {}
    },
    {
      "name": "register",
      "vhost": "vm",
      "durable": true,
      "auto_delete": false,
      "arguments": {}
    }
  ],
  "exchanges": [
    {
      "name": "to_cega",
      "vhost": "${MQ_VHOST:-/}",
      "type": "topic",
      "durable": true,
      "auto_delete": false,
      "internal": false,
      "arguments": {}
    },
    {
      "name": "sda",
      "vhost": "${MQ_VHOST:-/}",
      "type": "topic",
      "durable": true,
      "auto_delete": false,
      "internal": false,
      "arguments": {}
    },
    {
      "name": "vm",
      "vhost": "vm",
      "type": "topic",
      "durable": true,
      "auto_delete": false,
      "internal": false,
      "arguments": {}
    }
  ],
  "bindings": [
    {
        "source": "sda",
        "vhost": "${MQ_VHOST:-/}",
        "destination_type": "queue",
        "arguments": {},
        "destination": "archived",
        "routing_key": "archived"
    },
    {
        "source": "sda",
        "vhost": "${MQ_VHOST:-/}",
        "destination_type": "queue",
        "arguments": {},
        "destination": "accessionIDs",
        "routing_key": "accessionIDs"
    },
    {
        "source": "sda",
        "vhost": "${MQ_VHOST:-/}",
        "destination_type": "queue",
        "arguments": {},
        "destination": "backup",
        "routing_key": "backup"
    },
    {
        "source": "sda",
        "vhost": "${MQ_VHOST:-/}",
        "destination_type": "queue",
        "arguments": {},
        "destination": "completed",
        "routing_key": "completed"
    },
    {
        "source": "sda",
        "vhost": "${MQ_VHOST:-/}",
        "destination_type": "queue",
        "arguments": {},
        "destination": "error",
        "routing_key": "error"
    },
    {
        "source": "sda",
        "vhost": "${MQ_VHOST:-/}",
        "destination_type": "queue",
        "arguments": {},
        "destination": "files",
        "routing_key": "files"
    },
    {
        "source": "localega",
        "vhost": "${MQ_VHOST:-/}",
        "destination_type": "queue",
        "arguments": {},
        "destination": "inbox",
        "routing_key": "inbox"
    },
    {
        "source": "localega",
        "vhost": "${MQ_VHOST:-/}",
        "destination_type": "queue",
        "arguments": {},
        "destination": "ingest",
        "routing_key": "ingest"
    },
    {
        "source": "sda",
        "vhost": "${MQ_VHOST:-/}",
        "destination_type": "queue",
        "arguments": {},
        "destination": "mappings",
        "routing_key": "mappings"
    },
    {
        "source": "sda",
        "vhost": "${MQ_VHOST:-/}",
        "destination_type": "queue",
        "arguments": {},
        "destination": "verified",
        "routing_key": "verified"
    },
    {
        "source": "vm",
        "vhost": "vm",
        "destination_type": "queue",
        "arguments": {},
        "destination": "manager",
        "routing_key": "manager"
    },
    {
        "source": "vm",
        "vhost": "vm",
        "destination_type": "queue",
        "arguments": {},
        "destination": "register",
        "routing_key": "register"
    },
    {
        "source": "vm",
        "vhost": "vm",
        "destination_type": "queue",
        "arguments": {},
        "destination": "error",
        "routing_key": "error"
    }
  ]
}
EOF

if [ -n "${MQ_VHOST}" ];then
MQ_VHOST="/${MQ_VHOST}"
fi
cat > "/var/lib/rabbitmq/advanced.config" <<EOF
[
  {rabbit,  [
    {tcp_listeners, []}
  ]},
  {rabbitmq_shovel, [
    {shovels, [
      {to_cega, [
        {source, [
          {protocol, amqp091},
          {uris,[ "amqp://${MQ_VHOST:-}" ]},
          {declarations,  [
                            {'queue.declare', [{exclusive, true}]},
                            {'queue.bind', [{exchange, <<"to_cega">>}, {queue, <<>>}, {routing_key, <<"#">>}]}
                          ]},
          {queue, <<>>},
          {prefetch_count, 10}
        ]},
        {destination, [
                        {protocol, amqp091},
                        {uris, ["${CEGA_CONNECTION}"]},
                        {declarations, []},
                        {publish_properties, [{delivery_mode, 2}]},
                        {publish_fields, [{exchange, <<"localega.v1">>}]}
                      ]},
        {ack_mode, on_confirm},
        {reconnect_delay, 5}
      ]},
      {cega_completion, [
        {source,  [
                    {protocol, amqp091},
                    {uris, ["amqp://${MQ_VHOST:-}"]},
                    {declarations, [{'queue.declare', [{exclusive, true}] }, {'queue.bind', [{exchange, <<"sda">>}, {queue, <<>>}, {routing_key, <<"completed">>}] } ] },
                    {queue, <<>>},
                    {prefetch_count, 10}
                  ]},
        {destination, [
                        {protocol, amqp091},
                        {uris, ["amqp://${MQ_VHOST:-}"]},
                        {declarations, []},
                        {publish_properties, [{delivery_mode, 2}]},
                        {publish_fields, [{exchange, <<"to_cega">>},
                        {routing_key, <<"files.completed">>}
                      ]},
        {ack_mode, on_confirm},
        {reconnect_delay, 5}
        ]}
      ]},
      {cega_error, [
        {source,  [
                    {protocol, amqp091},
                    {uris, ["amqp://${MQ_VHOST:-}"]},
                    {declarations, [{'queue.declare', [{exclusive, true}] }, {'queue.bind', [{exchange, <<"sda">>}, {queue, <<>>}, {routing_key, <<"error">>}] } ] },
                    {queue, <<>>},
                    {prefetch_count, 10}
                  ]},
        {destination, [
                        {protocol, amqp091},
                        {uris, ["amqp://${MQ_VHOST:-}"]},
                        {declarations, []},
                        {publish_properties, [{delivery_mode, 2}]},
                        {publish_fields, [{exchange, <<"to_cega">>},
                        {routing_key, <<"files.error">>}
                      ]},
        {ack_mode, on_confirm},
        {reconnect_delay, 5}
        ]}
      ]},
      {cega_inbox, [
        {source,  [
                    {protocol, amqp091},
                    {uris, ["amqp://${MQ_VHOST:-}"]},
                    {declarations, [{'queue.declare', [{exclusive, true}] }, {'queue.bind', [{exchange, <<"sda">>}, {queue, <<>>}, {routing_key, <<"inbox">>}] } ] },
                    {queue, <<>>},
                    {prefetch_count, 10}
                  ]},
        {destination, [
                        {protocol, amqp091},
                        {uris, ["amqp://${MQ_VHOST:-}"]},
                        {declarations, []},
                        {publish_properties, [{delivery_mode, 2}]},
                        {publish_fields, [{exchange, <<"to_cega">>},
                        {routing_key, <<"files.inbox">>}
                      ]},
        {ack_mode, on_confirm},
        {reconnect_delay, 5}
        ]}
      ]},
      {cega_verified, [
        {source,  [
                    {protocol, amqp091},
                    {uris, ["amqp://${MQ_VHOST:-}"]},
                    {declarations, [{'queue.declare', [{exclusive, true}] }, {'queue.bind', [{exchange, <<"sda">>}, {queue, <<>>}, {routing_key, <<"verified">>}] } ] },
                    {queue, <<>>},
                    {prefetch_count, 10}
                  ]},
        {destination, [
                        {protocol, amqp091},
                        {uris, ["amqp://${MQ_VHOST:-}"]},
                        {declarations, []},
                        {publish_properties, [{delivery_mode, 2}]},
                        {publish_fields, [{exchange, <<"to_cega">>},
                        {routing_key, <<"files.verified">>}
                      ]},
        {ack_mode, on_confirm},
        {reconnect_delay, 5}
        ]}
      ]}
    ]}
  ]}
].
EOF
chmod 600 "/var/lib/rabbitmq/advanced.config"
else
cat > "/var/lib/rabbitmq/definitions.json" <<EOF
{
  "users": [
    {
      "name": "${MQ_USER}",
      "password_hash": "${MQ_PASSWORD_HASH}",
      "hashing_algorithm": "rabbit_password_hashing_sha256",
      "tags": "administrator"
    }
  ],
  "vhosts": [
    {
      "name": "${MQ_VHOST:-/}"
    },
    {
      "name": "vm"
    }
  ],
  "permissions": [
    {
      "user": "${MQ_USER}",
      "vhost": "${MQ_VHOST:-/}",
      "configure": ".*",
      "write": ".*",
      "read": ".*"
    },
    {
      "user": "${MQ_USER}",
      "vhost": "vm",
      "configure": ".*",
      "write": ".*",
      "read": ".*"
    }
  ],
  "parameters": [],
  "global_parameters": [
    {
      "name": "cluster_name",
      "value": "rabbit@localhost"
    }
  ],
  "policies": [
    {
      "name": "ha-all",
      "pattern": ".*",
      "vhost": "${MQ_VHOST:-/}",
      "definition": {
        "ha-mode": "all",
        "ha-sync-mode": "automatic",
        "ha-sync-batch-size": 1
      }
    },
    {
      "name": "ha-vm",
      "pattern": ".*",
      "vhost": "vm",
      "definition": {
        "ha-mode": "all",
        "ha-sync-mode": "automatic",
        "ha-sync-batch-size": 1
      }
    }
  ],
  "queues": [
    {
      "name": "archived",
      "vhost": "${MQ_VHOST:-/}",
      "durable": true,
      "auto_delete": false,
      "arguments": {}
    },
    {
      "name": "backup",
      "vhost": "${MQ_VHOST:-/}",
      "durable": true,
      "auto_delete": false,
      "arguments": {}
    },
    {
      "name": "completed",
      "vhost": "${MQ_VHOST:-/}",
      "durable": true,
      "auto_delete": false,
      "arguments": {}
    },
    {
      "name": "error",
      "vhost": "${MQ_VHOST:-/}",
      "durable": true,
      "auto_delete": false,
      "arguments": {}
    },
    {
      "name": "inbox",
      "vhost": "${MQ_VHOST:-/}",
      "durable": true,
      "auto_delete": false,
      "arguments": {}
    },
    {
      "name": "ingest",
      "vhost": "${MQ_VHOST:-/}",
      "durable": true,
      "auto_delete": false,
      "arguments": {}
    },
    {
      "name": "mappings",
      "vhost": "${MQ_VHOST:-/}",
      "durable": true,
      "auto_delete": false,
      "arguments": {}
    },
    {
      "name": "metadata",
      "vhost": "${MQ_VHOST:-/}",
      "durable": true,
      "auto_delete": false,
      "arguments": {}
    },
    {
      "name": "accessionIDs",
      "vhost": "${MQ_VHOST:-/}",
      "durable": true,
      "auto_delete": false,
      "arguments": {}
    },
    {
      "name": "verified",
      "vhost": "${MQ_VHOST:-/}",
      "durable": true,
      "auto_delete": false,
      "arguments": {}
    },
    {
      "name": "manager",
      "vhost": "vm",
      "durable": true,
      "auto_delete": false,
      "arguments": {}
    },
    {
      "name": "register",
      "vhost": "vm",
      "durable": true,
      "auto_delete": false,
      "arguments": {}
    },
    {
      "name": "error",
      "vhost": "vm",
      "durable": true,
      "auto_delete": false,
      "arguments": {}
    }
  ],
  "exchanges": [
    {
      "name": "sda",
      "vhost": "${MQ_VHOST:-/}",
      "type": "topic",
      "durable": true,
      "auto_delete": false,
      "internal": false,
      "arguments": {}
    },
    {
      "name": "vm",
      "vhost": "vm",
      "type": "topic",
      "durable": true,
      "auto_delete": false,
      "internal": false,
      "arguments": {}
    }
  ],
  "bindings": [
    {
        "source": "sda",
        "vhost": "${MQ_VHOST:-/}",
        "destination_type": "queue",
        "arguments": {},
        "destination": "archived",
        "routing_key": "archived"
    },
    {
        "source": "sda",
        "vhost": "${MQ_VHOST:-/}",
        "destination_type": "queue",
        "arguments": {},
        "destination": "accessionIDs",
        "routing_key": "accessionIDs"
    },
    {
        "source": "sda",
        "vhost": "${MQ_VHOST:-/}",
        "destination_type": "queue",
        "arguments": {},
        "destination": "backup",
        "routing_key": "backup"
    },
    {
        "source": "sda",
        "vhost": "${MQ_VHOST:-/}",
        "destination_type": "queue",
        "arguments": {},
        "destination": "completed",
        "routing_key": "completed"
    },
    {
        "source": "sda",
        "vhost": "${MQ_VHOST:-/}",
        "destination_type": "queue",
        "arguments": {},
        "destination": "error",
        "routing_key": "error"
    },
    {
        "source": "sda",
        "vhost": "${MQ_VHOST:-/}",
        "destination_type": "queue",
        "arguments": {},
        "destination": "inbox",
        "routing_key": "inbox"
    },
    {
        "source": "sda",
        "vhost": "${MQ_VHOST:-/}",
        "destination_type": "queue",
        "arguments": {},
        "destination": "ingest",
        "routing_key": "ingest"
    },
    {
        "source": "sda",
        "vhost": "${MQ_VHOST:-/}",
        "destination_type": "queue",
        "arguments": {},
        "destination": "mappings",
        "routing_key": "mappings"
    },
    {
        "source": "sda",
        "vhost": "${MQ_VHOST:-/}",
        "destination_type": "queue",
        "arguments": {},
        "destination": "metadata",
        "routing_key": "metadata"
    },
    {
        "source": "sda",
        "vhost": "${MQ_VHOST:-/}",
        "destination_type": "queue",
        "arguments": {},
        "destination": "verified",
        "routing_key": "verified"
    },
    {
        "source": "vm",
        "vhost": "vm",
        "destination_type": "queue",
        "arguments": {},
        "destination": "manager",
        "routing_key": "manager"
    },
    {
        "source": "vm",
        "vhost": "vm",
        "destination_type": "queue",
        "arguments": {},
        "destination": "register",
        "routing_key": "register"
    },
    {
        "source": "vm",
        "vhost": "vm",
        "destination_type": "queue",
        "arguments": {},
        "destination": "error",
        "routing_key": "error"
    }
  ]
}
EOF
fi

chmod 600 "/var/lib/rabbitmq/definitions.json"

exec "$@"
