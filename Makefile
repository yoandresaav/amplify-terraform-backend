

.PONY: up
up:
	zip file_assembly_lambda.zip file_assembly_lambda.py
	zip file_upload_lambda.zip file_upload_lambda.py
	terraform apply



.PONY: clean
clean:
	terraform destroy
	rm -rf ./*lambda.zip

