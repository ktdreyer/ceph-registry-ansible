all: playbook

playbook:
	ansible-playbook \
	  --vault-password-file=~/.vault_pass.txt \
	  -v \
	  -i inventory \
	  registry.yml
