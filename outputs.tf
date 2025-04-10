output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.main.dns_name
}

output "rds_endpoint" {
  description = "Endpoint address of the RDS MySQL instance"
  value       = aws_db_instance.mysql_rds.endpoint
  sensitive   = true
}

output "redis_endpoint" {
  description = "Endpoint address of the ElastiCache Redis instance (Primary Endpoint)"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].address
  sensitive   = true
}

output "redis_port" {
  description = "Port of the ElastiCache Redis instance"
  value       = aws_elasticache_cluster.redis.cache_nodes[0].port
  sensitive   = true
}