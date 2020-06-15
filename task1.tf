provider "aws" {
  region   = "ap-south-1"
  profile  = "pritam"
}

resource "tls_private_key" task1_p_key  {
  algorithm = "RSA"
}

resource "aws_key_pair" "task1-key" {
  key_name    = "task1-key"
  public_key = tls_private_key.task1_p_key.public_key_openssh
  }

resource "aws_security_group" "task1-sg" {
  name        = "task1-sg"
  description = "Allow TLS inbound traffic"
  vpc_id      = "vpc-d60e12be"


  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "task1-sg"
  }
}

resource "aws_instance" "task1-inst" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  availability_zone = "ap-south-1a"
  key_name      = "task1-key"
  security_groups = [ "task1-sg" ]
 
   connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key =  tls_private_key.task1_p_key.private_key_pem
    host     = aws_instance.task1-inst.public_ip
  }

 provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }

tags = {
    Name = "task1-inst"
  }
}

resource "aws_ebs_volume" "task1-ebs" {
  availability_zone = "ap-south-1a"
  size              = 1

  tags = {
    Name = "task1-ebs"
  }
}

resource "aws_volume_attachment" "task1-attach" {
 device_name = "/dev/sdh"
 volume_id    = "${aws_ebs_volume.task1-ebs.id}"
 instance_id  = "${aws_instance.task1-inst.id}"
 force_detach = true
}

output "myos_ip" {
  value = aws_instance.task1-inst.public_ip
}	

resource "null_resource" "null_instan_ip"  {
	provisioner "local-exec" {
	    command = "echo  ${aws_instance.task1-inst.public_ip} > publicip.txt"
  	}
}

resource "null_resource" "null_vol_attach"  {

depends_on = [
    aws_volume_attachment.task1-attach,
  ]


 connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.task1_p_key.private_key_pem
    host     = aws_instance.task1-inst.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/Pritam002-cybey/AWS-Task-1/hybrid-task1.git /var/www/html/"
    ]
  }
}

resource "null_resource" "null_vol_depend"  {

depends_on = [
    null_resource.null_vol_attach,
  ]
}


#To create S3 bucket
resource "aws_s3_bucket" "my-terraform-bucket-78965" {
  bucket = "my-terraform-bucket-78965"
  acl    = "public-read"
  force_destroy  = true
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST"]
    allowed_origins = ["https://my-terraform-bucket-78965"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
depends_on = [
   aws_volume_attachment.task1-attach,
  ]
}

#To upload data to S3 bucket
resource "null_resource" "remove_and_upload_to_s3" {
  provisioner "local-exec" {
    command ="C:/Users/91989/Desktop/terraform/hybrid-task1-master/index.html"
}	
depends_on = [
   aws_s3_bucket.my-terraform-bucket-78965,
  ]
}

# Create Cloudfront distribution
resource "aws_cloudfront_distribution" "distribution" {
    origin {
        domain_name = "${aws_s3_bucket.my-terraform-bucket-78965.bucket_regional_domain_name}"
        origin_id = "S3-${aws_s3_bucket.my-terraform-bucket-78965.bucket}"

        custom_origin_config {
            http_port = 80
            https_port = 443
            origin_protocol_policy = "match-viewer"
            origin_ssl_protocols = ["TLSv1", "TLSv1.1", "TLSv1.2"]
        }
}
    # By default, show index.html file
    default_root_object = "index.html"
    enabled = true

    # If there is a 404, return index.html with a HTTP 200 Response
    custom_error_response {
        error_caching_min_ttl = 3000
        error_code = 404
        response_code = 200
        response_page_path = "/index.html"
    }

    default_cache_behavior {
        allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods = ["GET", "HEAD"]
        target_origin_id = "S3-${aws_s3_bucket.my-terraform-bucket-78965.bucket}"

        #Not Forward all query strings, cookies and headers
        forwarded_values {
            query_string = false
	    cookies {
		forward = "none"
	    }
            
        }

        viewer_protocol_policy = "redirect-to-https"
        min_ttl = 0
        default_ttl = 3600
        max_ttl = 86400
    }

    # Distributes content to all
    price_class = "PriceClass_All"

    # Restricts who is able to access this content
    restrictions {
        geo_restriction {
            # type of restriction, blacklist, whitelist or none
            restriction_type = "none"
        }
    }

    # SSL certificate for the service.
    viewer_certificate {
        cloudfront_default_certificate = true
    }
}
output "cloudfront_ip_addr" {
  value = aws_cloudfront_distribution.distribution.domain_name
