# kubernetes/secret.yaml.tpl
apiVersion: v1
kind: Secret
metadata:
  name: db-credentials
type: Opaque
data:
  db_url: ${DB_URL_BASE64}
  db_username: ${DB_USERNAME_BASE64}
  db_password: ${DB_PASSWORD_BASE64}
  db_host: ${DB_HOST_BASE64}
  db_port: ${DB_PORT_BASE64}
  db_name: ${DB_NAME_BASE64}