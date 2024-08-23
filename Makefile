

.PONY: up
up:
	terraform apply



.PONY: clean
clean:
	rm -rf ./*.zip

.PONY: destroy
destroy:
	rm -rf ./*.zip
	terraform destroy
