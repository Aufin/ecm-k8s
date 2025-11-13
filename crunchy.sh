alias minikube='sudo minikube'
alias kubectl='sudo kubectl'

mrestart () {
	minikube delete
	# sudo and minikube make locks strange
	sudo sysctl fs.protected_regular=0
	rm -v /tmp/juju-mk*

	minikube start --disk-size=64g --force
    minikube mount --uid 1001 --gid 1001 /srv/share-test:/share &
 
}

k-run-testpod () {
 kubectl run -it --rm testpod --image=alpine --restart=Never
}

k-setup () {
	csi-setup && \
		k-ecm-namespace && \
		k-ecm-storage && \
		apply-CPK
}

k-nfs-setup () {
  k-ecm-nfs-service
  echo Waiting for it to be ready ...
  kubectl wait --for=condition=Ready pod/nfs-server-0 --timeout=60s
  k-ecm-nfs-storage
}

k-db-setup () {
 kubectl apply -f ecm-db-shared-volume.yaml
 #echo waiting for pvc to be bound
 #kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc/pvc-ecm-shared-with-db
 apply-ecm-db
}		

k-db-init () {
 DUMP=${1:-db-dump-2025-10-10.sql}
 export PG_CLUSTER_PRIMARY_POD=$(kubectl get pod -o name -l postgres-operator.crunchydata.com/cluster=ecm-db,postgres-operator.crunchydata.com/role=master)
 kubectl exec $PG_CLUSTER_PRIMARY_POD -- psql --echo-all -f /tablespaces/shared/$DUMP
}

csi-setup () {
     cd csi-driver-nfs
     sudo ./deploy/install-driver.sh v4.12.1 local
     cd -
}

nfs-pod () {
  kubectl get pod -lapp=nfs-server -oname
}

k-ecm-namespace  () {
	kubectl apply -f ecm-namespace.yaml
    kubectl config set-context --current --namespace=ecm
    
}

k-ecm-storage () {
	kubectl apply -f local-persistent-volumes.yaml
	kubectl apply -f local-storage-classes.yaml
    
}

k-ecm-nfs-service () {
	kubectl apply -f ecm-global-pvc.yaml
    kubectl apply -n ecm -f ecm-nfs-deployment.yaml 
    kubectl apply -n ecm -f ecm-nfs-service.yaml
}

k-ecm-nfs-storage () {
	kubectl apply -f ecm-shared-class.yaml
	kubectl apply -f ecm-shared-volume.yaml
	kubectl apply -f ecm-shared-claim.yaml
}



apply-CPK () {
    kubectl exec nfs-server-0 -- mkdir /exports/pg-backrest
	kubectl apply -k kustomize/install/namespace
	kubectl apply --server-side -k kustomize/install/default/
}

apply-ecm-db () {
	kubectl apply -k kustomize/ecm-db/
}

export-kenv () {
    export PGO_POD=$(kubectl get -n postgres-operator -o name -l app.kubernetes.io/name=pgo pod)
	export PG_CLUSTER_INSTANCE_1=$(kubectl get pod -n postgres-operator -o name -l postgres-operator.crunchydata.com/cluster=ecm-db,postgres-operator.crunchydata.com/instance-set=instance1)
}




do-over () {
	mrestart
	kstorage
	apply-CPK
    sleep 1
	export-kenv
	while [ -z $PGO_POD ]; do echo no pod? ; kubectl get -n postgres-operator pod; sleep 1; export-kenv ; done;
	kubectl wait --for=condition=Ready $PGO_POD --timeout=60s
	apply-ecm-db
	export-kenv
}


# export SHARED_VOLUME_NAME=$(kubectl get -n postgres-operator -o=jsonpath='{.items[*].spec.volumeName}' -l postgres-operator.crunchydata.com/data=shared,postgres-operator.crunchydata.com/cluster=ecm-db,postgres-operator.crunchydata.com/role=tablespace pvc)

# kubectl label pv $SHARED_VOLUME_NAME shared-ecm-db=pv
