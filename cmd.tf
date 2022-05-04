variable "v_vpc_cidr" {
default  ="10.0.0.0/16"
}

data aws_availability_zones "azs"{
}

resource aws_vpc "vpc1"{
    cidr_block=var.v_vpc_cidr
	tags = {
    Name = "TF-VPC1"
  }
}
resource aws_subnet "sn"{
   count=length(data.aws_availability_zones.azs.names)*2
   cidr_block=cidrsubnet(var.v_vpc_cidr, 6,count.index)
   vpc_id=aws_vpc.vpc1.id
   availability_zone=data.aws_availability_zones.azs.names[count.index%length(data.aws_availability_zones.azs.names)]
   map_public_ip_on_launch=length(data.aws_availability_zones.azs.names)>count.index?true:false
   tags={
   "Name"="sn-${count.index}"
   }
}
						
resource aws_internet_gateway "igw" {
	vpc_id = aws_vpc.vpc1.id
	}

resource aws_eip "eip" {
}

resource aws_nat_gateway "nat"{
	allocation_id = aws_eip.eip.id
	subnet_id = aws_subnet.sn[0].id
	}
resource aws_route_table "rt" {
count = 2
vpc_id =aws_vpc.vpc1.id
	route {
			cidr_block = "0.0.0.0/0"
			gateway_id = count.index==0? aws_internet_gateway.igw.id : aws_nat_gateway.nat.id 
			}
			}
resource "aws_route_table_association" "rta" {
  count  		 =length(data.aws_availability_zones.azs.names)
  subnet_id      = count.index<3? aws_subnet.sn.*.id[count.index%length(data.aws_availability_zones.azs.names)]:aws_subnet.sn.*.id[count.index+3%length(data.aws_availability_zones.azs.names)*3]
  route_table_id = count.index<3? aws_route_table.rt[0].id : aws_route_table.rt[1].id
}




resource "aws_lb_target_group" "my-target-group" {
  health_check {
    interval            = 10
    path                = "/"
    protocol            = "HTTP"
    timeout             = 5
    healthy_threshold   = 5
    unhealthy_threshold = 2
  }

  name        = "my-test-tg"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.vpc1.id
}
resource "aws_lb" "my-aws-alb" {
  name     = "my-test-alb"
  internal = false

  security_groups = [
    "${aws_security_group.my-alb-sg.id}",
  ]
  subnets            = slice(aws_subnet.sn.*.id,0,3)


  tags = {
    Name = "my-test-alb"
  }

  ip_address_type    = "ipv4"
  load_balancer_type = "application"
}

resource "aws_lb_listener" "my-test-alb-listner" {
  load_balancer_arn = "${aws_lb.my-aws-alb.arn}"
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.my-target-group.arn}"
  }
} 

resource "aws_security_group" "my-alb-sg" {
  name   = "my-alb-sg"
  vpc_id = aws_vpc.vpc1.id
}

resource "aws_security_group_rule" "inbound_ssh" {
  from_port         = 22
  protocol          = "tcp"
  security_group_id = "${aws_security_group.my-alb-sg.id}"
  to_port           = 22
  type              = "ingress"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "inbound_http" {
  from_port         = 80
  protocol          = "tcp"
  security_group_id = "${aws_security_group.my-alb-sg.id}"
  to_port           = 80
  type              = "ingress"
  cidr_blocks       = ["0.0.0.0/0"]
}
resource "aws_security_group_rule" "inbound_http2" {
  from_port         = 8080
  protocol          = "tcp"
  security_group_id = "${aws_security_group.my-alb-sg.id}"
  to_port           = 8080
  type              = "ingress"
  cidr_blocks       = ["0.0.0.0/0"]
}
resource "aws_security_group_rule" "inbound_http3" {
  from_port         = 90
  protocol          = "tcp"
  security_group_id = "${aws_security_group.my-alb-sg.id}"
  to_port           = 90
  type              = "ingress"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "outbound_all" {
  from_port         = 0
  protocol          = "-1"
  security_group_id = "${aws_security_group.my-alb-sg.id}"
  to_port           = 0
  type              = "egress"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource aws_instance "s1" {
count = length(data.aws_availability_zones.azs.names)
ami =  "ami-0756a1c858554433e"
vpc_security_group_ids = [aws_security_group.my-alb-sg.id]
subnet_id =aws_subnet.sn.*.id[count.index%length(data.aws_availability_zones.azs.names)]
instance_type = "c5.large"
key_name = "naina"
user_data = <<EOF
#!/bin/bash
sudo apt-get update
sudo apt-get install apache2 -y 
EOF
	


depends_on = [aws_nat_gateway.nat]
tags = {
Name = join("-",["instance",count.index])
}
}


resource aws_instance "basion" {
ami = "ami-0756a1c858554433e"
instance_type = "t2.micro"
vpc_security_group_ids = [aws_security_group.my-alb-sg.id]
subnet_id = aws_subnet.sn[0].id
key_name = "naina"
user_data = <<EOF
#!/bin/bash
sudo apt-get update
sudo apt-get install apache2 -y 
		
EOF
	tags = {
		Name = "Terraform"	
		Batch = "5AM"
	}

}
resource "aws_lb_target_group_attachment" "tga" {
count = length(data.aws_availability_zones.azs.names)
  target_group_arn = "${aws_lb_target_group.my-target-group.arn}"
  target_id        = count.index==0? aws_instance.s1.*.id[0]:aws_instance.s1.*.id[1]
  port             = 80
}
resource aws_vpc_endpoint "vpce" {
  vpc_id       = aws_vpc.vpc1.id
  subnet_ids  = slice(aws_subnet.sn.*.id,3,5)
  service_name = "com.amazonaws.ap-south-1.s3"
  vpc_endpoint_type = "Interface"
  security_group_ids = [aws_security_group.my-alb-sg.id]
  
  tags = { 
  Name = "vpce" 
  }
} 

resource "aws_launch_configuration" "lc" {

name          = "sam-lc"
image_id      = "ami-0756a1c858554433e"
/*security_group_id = [aws_security_group.my-alb-sg.id]*/
instance_type = "c5.large"
key_name = "naina"
user_data = <<EOF
#!/bin/bash
sudo apt-get update
sudo apt-get install apache2 -y 
EOF
}

resource "aws_autoscaling_group" "asg" {
  /*count = length(data.aws_availability_zones.azs.names)*/
  /*availability_zones = ["ap-south-1a"]*/
  desired_capacity   = 2
  max_size           = 3
  min_size           = 1
  health_check_grace_period = 300
  health_check_type         = "ELB"
  launch_configuration =aws_launch_configuration.lc.name
  vpc_zone_identifier  = slice(aws_subnet.sn.*.id,3,5)
  /*availability_zone = data.aws_availability_zones.azs.names[count.index%length(data.aws_availability_zones.azs.names)]*/
  
 
}
resource "aws_autoscaling_attachment" "asg_attachment_tg" {
  autoscaling_group_name = aws_autoscaling_group.asg.id
  lb_target_group_arn    = "${aws_lb_target_group.my-target-group.arn}"
}