output "ssm_connection_command" {
  description = "SSM Session Manager command to connect to the instance"
  value       = "aws ssm start-session --target ${aws_instance.grafana.id} --region ${data.aws_region.current.region} --document-name AWS-StartPortForwardingSession --parameters 'portNumber=3000,localPortNumber=3000'"
}

output "grafana_url" {
  description = "URL to access Grafana (after establishing SSM port forwarding)"
  value       = "http://localhost:3000"
}
