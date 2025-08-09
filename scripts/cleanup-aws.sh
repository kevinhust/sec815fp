#!/bin/bash

# AWS SIEM Environment Cleanup Script
set -e

CLUSTER_NAME="siem-eks-cluster"
REGION="us-east-1"

echo "🧹 开始清理AWS SIEM环境..."

# Function to wait for node group deletion
wait_for_nodegroup_deletion() {
    echo "⏳ 等待节点组删除完成..."
    while true; do
        status=$(aws eks describe-nodegroup --cluster-name $CLUSTER_NAME --nodegroup-name $CLUSTER_NAME-nodes --query 'nodegroup.status' --output text 2>/dev/null || echo "DELETED")
        if [ "$status" == "DELETED" ]; then
            echo "✅ 节点组已删除"
            break
        fi
        echo "   状态: $status - 继续等待..."
        sleep 30
    done
}

# Function to delete EKS cluster
delete_eks_cluster() {
    echo "🗑️  删除EKS集群..."
    aws eks delete-cluster --name $CLUSTER_NAME || echo "集群可能已删除"
    
    echo "⏳ 等待集群删除完成..."
    while true; do
        status=$(aws eks describe-cluster --name $CLUSTER_NAME --query 'cluster.status' --output text 2>/dev/null || echo "DELETED")
        if [ "$status" == "DELETED" ]; then
            echo "✅ EKS集群已删除"
            break
        fi
        echo "   集群状态: $status - 继续等待..."
        sleep 30
    done
}

# Function to delete VPCs
delete_vpcs() {
    echo "🗑️  删除SIEM VPC..."
    
    # Get all SIEM VPCs
    vpc_ids=$(aws ec2 describe-vpcs --filters "Name=tag:Project,Values=SIEM" --query 'Vpcs[*].VpcId' --output text)
    
    for vpc_id in $vpc_ids; do
        if [ "$vpc_id" != "None" ] && [ ! -z "$vpc_id" ]; then
            echo "   删除VPC: $vpc_id"
            
            # Delete NAT Gateways first
            nat_gws=$(aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc_id" --query 'NatGateways[*].NatGatewayId' --output text)
            for nat_gw in $nat_gws; do
                if [ "$nat_gw" != "None" ] && [ ! -z "$nat_gw" ]; then
                    echo "     删除NAT Gateway: $nat_gw"
                    aws ec2 delete-nat-gateway --nat-gateway-id $nat_gw
                fi
            done
            
            # Wait a bit for NAT Gateways to delete
            sleep 30
            
            # Delete Internet Gateways
            igw_ids=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc_id" --query 'InternetGateways[*].InternetGatewayId' --output text)
            for igw_id in $igw_ids; do
                if [ "$igw_id" != "None" ] && [ ! -z "$igw_id" ]; then
                    echo "     分离并删除Internet Gateway: $igw_id"
                    aws ec2 detach-internet-gateway --internet-gateway-id $igw_id --vpc-id $vpc_id
                    aws ec2 delete-internet-gateway --internet-gateway-id $igw_id
                fi
            done
            
            # Delete Security Groups (except default)
            sg_ids=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc_id" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text)
            for sg_id in $sg_ids; do
                if [ "$sg_id" != "None" ] && [ ! -z "$sg_id" ]; then
                    echo "     删除安全组: $sg_id"
                    aws ec2 delete-security-group --group-id $sg_id || echo "     安全组删除失败，可能仍被使用"
                fi
            done
            
            # Delete Subnets
            subnet_ids=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc_id" --query 'Subnets[*].SubnetId' --output text)
            for subnet_id in $subnet_ids; do
                if [ "$subnet_id" != "None" ] && [ ! -z "$subnet_id" ]; then
                    echo "     删除子网: $subnet_id"
                    aws ec2 delete-subnet --subnet-id $subnet_id
                fi
            done
            
            # Delete Route Tables (except main)
            rt_ids=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc_id" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text)
            for rt_id in $rt_ids; do
                if [ "$rt_id" != "None" ] && [ ! -z "$rt_id" ]; then
                    echo "     删除路由表: $rt_id"
                    aws ec2 delete-route-table --route-table-id $rt_id
                fi
            done
            
            # Finally delete VPC
            echo "     删除VPC: $vpc_id"
            aws ec2 delete-vpc --vpc-id $vpc_id || echo "     VPC删除失败"
        fi
    done
}

# Function to delete IAM roles
delete_iam_roles() {
    echo "🗑️  删除IAM角色..."
    
    roles=("siem-eks-cluster-cluster-role" "siem-eks-cluster-node-role")
    
    for role in "${roles[@]}"; do
        echo "   检查角色: $role"
        
        # Detach policies first
        policies=$(aws iam list-attached-role-policies --role-name $role --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null || echo "")
        for policy in $policies; do
            if [ "$policy" != "None" ] && [ ! -z "$policy" ]; then
                echo "     分离策略: $policy"
                aws iam detach-role-policy --role-name $role --policy-arn $policy
            fi
        done
        
        # Delete instance profiles if any
        profiles=$(aws iam list-instance-profiles-for-role --role-name $role --query 'InstanceProfiles[*].InstanceProfileName' --output text 2>/dev/null || echo "")
        for profile in $profiles; do
            if [ "$profile" != "None" ] && [ ! -z "$profile" ]; then
                echo "     从实例配置文件删除角色: $profile"
                aws iam remove-role-from-instance-profile --instance-profile-name $profile --role-name $role
                aws iam delete-instance-profile --instance-profile-name $profile
            fi
        done
        
        # Delete role
        echo "     删除角色: $role"
        aws iam delete-role --role-name $role 2>/dev/null || echo "     角色删除失败或不存在"
    done
}

# Function to release Elastic IPs
release_eips() {
    echo "🗑️  释放弹性IP..."
    
    eip_allocs=$(aws ec2 describe-addresses --filters "Name=tag:Project,Values=SIEM" --query 'Addresses[*].AllocationId' --output text 2>/dev/null || echo "")
    for eip in $eip_allocs; do
        if [ "$eip" != "None" ] && [ ! -z "$eip" ]; then
            echo "   释放EIP: $eip"
            aws ec2 release-address --allocation-id $eip
        fi
    done
}

# Execute cleanup in order
wait_for_nodegroup_deletion
delete_eks_cluster

# Wait a bit before cleaning up VPC resources
echo "⏳ 等待60秒让EKS资源完全释放..."
sleep 60

delete_iam_roles
release_eips
delete_vpcs

echo "✅ AWS SIEM环境清理完成！"
