all: prod

prod dev:
	ansible-playbook \
	  --vault-password-file=~/.vault_pass.txt \
	  -v \
	  -i inventory \
	  $@.yml
