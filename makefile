PROTO_DIR=proto
PROTO_FILES=$(wildcard $(PROTO_DIR)/*.proto)

# pb/ is gitignored: it is generated here and published to the master branch
# by CI. protoc does not create the output directory, so it has to exist.
generate:
	mkdir -p pb
	protoc \
	--proto_path=$(PROTO_DIR) \
	--go_out=pb --go_opt=paths=source_relative \
	--go-grpc_out=pb --go-grpc_opt=paths=source_relative \
	$(PROTO_FILES)
