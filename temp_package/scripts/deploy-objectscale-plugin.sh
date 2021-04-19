#!/bin/bash 
##
## Copyright (c) 2020. Dell Inc. or its subsidiaries. All Rights Reserved.
##
## This software contains the intellectual property of Dell Inc.
## or is licensed to Dell Inc. from third parties. Use of this software
## and the intellectual property contained therein is expressly limited to the
## terms and conditions of the License Agreement under which it is provided by or
## on behalf of Dell Inc. or its subsidiaries.

service_id="objectscale"

echomsg () {

    if [ ! -d ./log ]
    then 
	    mkdir ./log
    fi 

    curdate=$(date +"%y.%m.%d %H:%M:%S")

    case $1 in
	    log)
	        msg=$2
            echo "$curdate : $msg"  >> $logfile
	        return
	        ;;
	    stl|starline)
	        msg="**********************************************"
	        ;;
	    dl|doubleline)
	        msg="=============================================="
	        ;;
        sl|singleline)
	        msg="----------------------------------------------"
	        ;;
        nl|newline)
	        msg=" "
	        ;;
	    *)
	        msg="$1"
	        ;;
    esac

    ## ok now show the message
    echo "$curdate : $msg" | tee -a $logfile

} #end echomsg

## add_vsphere7_clusterole_rules 
## Add rules needed to apply our plugin
add_vsphere7_clusterrole_rules () {
  vsphere7AppRoles="kubectl get -n vmware-system-appplatform-operator-system clusterrole vmware-system-appplatform-operator-manager-role  -o yaml"
  numRoles=$(eval ${vsphere7AppRoles} | egrep -c -e "- app.k8s.io")

  if [ ${numRoles} -le 3 ] 
  then
      echomsg "Adding roles to app platform"
      cat <<'EOT' > /tmp/newrules.yaml
- apiGroups:
  - app.k8s.io
  resources:
  - applications
  verbs:
  - '*'
EOT
      eval ${vsphere7AppRoles} > /tmp/currrules.yaml
      kubectl apply -f <(cat <(cat /tmp/currrules.yaml) /tmp/newrules.yaml)
      if [ $? -ne 0 ] 
      then
          echomsg "Error: unable to apply the clusterrole rules for clusterrole vmware-system-appplatform-operator-manager-role"
          exit 1
      fi
  fi 
}
## main()
curdate=`date +"%y%m%d"`
logfile="./log/deploy-objectscale-$curdate.log"

echomsg "Starting deployment of ObjectScale"
echomsg dl

echomsg "Locating kubectl..."
kubectl version --short=true > /tmp/kubectl_version.txt
if [ $? -ne 0 ]
then
    echomsg "error unable to located kubectl in the PATH"
    exit 1
fi 
kctlVers=$(cat /tmp/kubectl_version.txt)
echomsg "$kctlVers"

kubectl -n vmware-system-appplatform-operator-system get cm ${service_id} 2>/dev/null
if [ $? -eq 0 ]
then
    echomsg "ObjectScale Plugin \"${service_id}\" has already been deployed"
    echomsg "It must be disabled and removed before a new one can be applied"
    exit 1
fi

## Now check if the api groups have been added for VMware vSphere7 app platform:
add_vsphere7_clusterrole_rules

echomsg dl 
echomsg "Adding the ObjectScale plugin for vSphere7"

## rest of the code below is built with vmware/vmware_pack.sh
cat <<'EOF' | kubectl apply -f -
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: objectscale
  namespace: vmware-system-appplatform-operator-system
  labels:
    appplatform.vmware.com/kind: supervisorservice
data:
  objectscale-crd.yaml: |-


    ---
    apiVersion: apiextensions.k8s.io/v1beta1
    kind: CustomResourceDefinition
    metadata:
      annotations:
        controller-gen.kubebuilder.io/version: v0.2.5
      creationTimestamp: null
      name: applications.app.k8s.io
    spec:
      additionalPrinterColumns:
      - JSONPath: .spec.descriptor.type
        description: The type of the application
        name: Type
        type: string
      - JSONPath: .spec.descriptor.version
        description: The creation date
        name: Version
        type: string
      - JSONPath: .spec.addOwnerRef
        description: The application object owns the matched resources
        name: Owner
        type: boolean
      - JSONPath: .status.componentsReady
        description: Numbers of components ready
        name: Ready
        type: string
      - JSONPath: .metadata.creationTimestamp
        description: The creation date
        name: Age
        type: date
      group: app.k8s.io
      names:
        categories:
        - all
        kind: Application
        listKind: ApplicationList
        plural: applications
        shortNames:
        - app
        singular: application
      scope: Namespaced
      subresources:
        status: {}
      validation:
        openAPIV3Schema:
          description: Application is the Schema for the applications API
          properties:
            apiVersion:
              description: 'APIVersion defines the versioned schema of this representation
                of an object. Servers should convert recognized schemas to the latest
                internal value, and may reject unrecognized values. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources'
              type: string
            kind:
              description: 'Kind is a string value representing the REST resource this
                object represents. Servers may infer this from the endpoint the client
                submits requests to. Cannot be updated. In CamelCase. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
              type: string
            metadata:
              type: object
            spec:
              description: ApplicationSpec defines the specification for an Application.
              properties:
                addOwnerRef:
                  description: AddOwnerRef objects - flag to indicate if we need to add
                    OwnerRefs to matching objects Matching is done by using Selector to
                    query all ComponentGroupKinds
                  type: boolean
                assemblyPhase:
                  description: AssemblyPhase represents the current phase of the application's
                    assembly. An empty value is equivalent to "Succeeded".
                  type: string
                componentKinds:
                  description: ComponentGroupKinds is a list of Kinds for Application's
                    components (e.g. Deployments, Pods, Services, CRDs). It can be used
                    in conjunction with the Application's Selector to list or watch the
                    Applications components.
                  items:
                    description: GroupKind specifies a Group and a Kind, but does not
                      force a version.  This is useful for identifying concepts during
                      lookup stages without having partially valid types
                    properties:
                      group:
                        type: string
                      kind:
                        type: string
                    required:
                    - group
                    - kind
                    type: object
                  type: array
                descriptor:
                  description: Descriptor regroups information and metadata about an application.
                  properties:
                    description:
                      description: Description is a brief string description of the Application.
                      type: string
                    icons:
                      description: Icons is an optional list of icons for an application.
                        Icon information includes the source, size, and mime type.
                      items:
                        description: ImageSpec contains information about an image used
                          as an icon.
                        properties:
                          size:
                            description: (optional) The size of the image in pixels (e.g.,
                              25x25).
                            type: string
                          src:
                            description: The source for image represented as either an
                              absolute URL to the image or a Data URL containing the image.
                              Data URLs are defined in RFC 2397.
                            type: string
                          type:
                            description: (optional) The mine type of the image (e.g.,
                              "image/png").
                            type: string
                        required:
                        - src
                        type: object
                      type: array
                    keywords:
                      description: Keywords is an optional list of key words associated
                        with the application (e.g. MySQL, RDBMS, database).
                      items:
                        type: string
                      type: array
                    links:
                      description: Links are a list of descriptive URLs intended to be
                        used to surface additional documentation, dashboards, etc.
                      items:
                        description: Link contains information about an URL to surface
                          documentation, dashboards, etc.
                        properties:
                          description:
                            description: Description is human readable content explaining
                              the purpose of the link.
                            type: string
                          url:
                            description: Url typically points at a website address.
                            type: string
                        type: object
                      type: array
                    maintainers:
                      description: Maintainers is an optional list of maintainers of the
                        application. The maintainers in this list maintain the the source
                        code, images, and package for the application.
                      items:
                        description: ContactData contains information about an individual
                          or organization.
                        properties:
                          email:
                            description: Email is the email address.
                            type: string
                          name:
                            description: Name is the descriptive name.
                            type: string
                          url:
                            description: Url could typically be a website address.
                            type: string
                        type: object
                      type: array
                    notes:
                      description: Notes contain a human readable snippets intended as
                        a quick start for the users of the Application. CommonMark markdown
                        syntax may be used for rich text representation.
                      type: string
                    owners:
                      description: Owners is an optional list of the owners of the installed
                        application. The owners of the application should be contacted
                        in the event of a planned or unplanned disruption affecting the
                        application.
                      items:
                        description: ContactData contains information about an individual
                          or organization.
                        properties:
                          email:
                            description: Email is the email address.
                            type: string
                          name:
                            description: Name is the descriptive name.
                            type: string
                          url:
                            description: Url could typically be a website address.
                            type: string
                        type: object
                      type: array
                    type:
                      description: Type is the type of the application (e.g. WordPress,
                        MySQL, Cassandra).
                      type: string
                    version:
                      description: Version is an optional version indicator for the Application.
                      type: string
                  type: object
                info:
                  description: Info contains human readable key,value pairs for the Application.
                  items:
                    description: InfoItem is a human readable key,value pair containing
                      important information about how to access the Application.
                    properties:
                      name:
                        description: Name is a human readable title for this piece of
                          information.
                        type: string
                      type:
                        description: Type of the value for this InfoItem.
                        type: string
                      value:
                        description: Value is human readable content.
                        type: string
                      valueFrom:
                        description: ValueFrom defines a reference to derive the value
                          from another source.
                        properties:
                          configMapKeyRef:
                            description: Selects a key of a ConfigMap.
                            properties:
                              apiVersion:
                                description: API version of the referent.
                                type: string
                              fieldPath:
                                description: 'If referring to a piece of an object instead
                                  of an entire object, this string should contain a valid
                                  JSON/Go field access statement, such as desiredState.manifest.containers[2].
                                  For example, if the object reference is to a container
                                  within a pod, this would take on a value like: "spec.containers{name}"
                                  (where "name" refers to the name of the container that
                                  triggered the event) or if no container name is specified
                                  "spec.containers[2]" (container with index 2 in this
                                  pod). This syntax is chosen only to have some well-defined
                                  way of referencing a part of an object. TODO: this design
                                  is not final and this field is subject to change in
                                  the future.'
                                type: string
                              key:
                                description: The key to select.
                                type: string
                              kind:
                                description: 'Kind of the referent. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
                                type: string
                              name:
                                description: 'Name of the referent. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names'
                                type: string
                              namespace:
                                description: 'Namespace of the referent. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/'
                                type: string
                              resourceVersion:
                                description: 'Specific resourceVersion to which this reference
                                  is made, if any. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#concurrency-control-and-consistency'
                                type: string
                              uid:
                                description: 'UID of the referent. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#uids'
                                type: string
                            type: object
                          ingressRef:
                            description: Select an Ingress.
                            properties:
                              apiVersion:
                                description: API version of the referent.
                                type: string
                              fieldPath:
                                description: 'If referring to a piece of an object instead
                                  of an entire object, this string should contain a valid
                                  JSON/Go field access statement, such as desiredState.manifest.containers[2].
                                  For example, if the object reference is to a container
                                  within a pod, this would take on a value like: "spec.containers{name}"
                                  (where "name" refers to the name of the container that
                                  triggered the event) or if no container name is specified
                                  "spec.containers[2]" (container with index 2 in this
                                  pod). This syntax is chosen only to have some well-defined
                                  way of referencing a part of an object. TODO: this design
                                  is not final and this field is subject to change in
                                  the future.'
                                type: string
                              host:
                                description: The optional host to select.
                                type: string
                              kind:
                                description: 'Kind of the referent. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
                                type: string
                              name:
                                description: 'Name of the referent. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names'
                                type: string
                              namespace:
                                description: 'Namespace of the referent. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/'
                                type: string
                              path:
                                description: The optional HTTP path.
                                type: string
                              protocol:
                                description: Protocol for the ingress
                                type: string
                              resourceVersion:
                                description: 'Specific resourceVersion to which this reference
                                  is made, if any. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#concurrency-control-and-consistency'
                                type: string
                              uid:
                                description: 'UID of the referent. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#uids'
                                type: string
                            type: object
                          secretKeyRef:
                            description: Selects a key of a Secret.
                            properties:
                              apiVersion:
                                description: API version of the referent.
                                type: string
                              fieldPath:
                                description: 'If referring to a piece of an object instead
                                  of an entire object, this string should contain a valid
                                  JSON/Go field access statement, such as desiredState.manifest.containers[2].
                                  For example, if the object reference is to a container
                                  within a pod, this would take on a value like: "spec.containers{name}"
                                  (where "name" refers to the name of the container that
                                  triggered the event) or if no container name is specified
                                  "spec.containers[2]" (container with index 2 in this
                                  pod). This syntax is chosen only to have some well-defined
                                  way of referencing a part of an object. TODO: this design
                                  is not final and this field is subject to change in
                                  the future.'
                                type: string
                              key:
                                description: The key to select.
                                type: string
                              kind:
                                description: 'Kind of the referent. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
                                type: string
                              name:
                                description: 'Name of the referent. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names'
                                type: string
                              namespace:
                                description: 'Namespace of the referent. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/'
                                type: string
                              resourceVersion:
                                description: 'Specific resourceVersion to which this reference
                                  is made, if any. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#concurrency-control-and-consistency'
                                type: string
                              uid:
                                description: 'UID of the referent. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#uids'
                                type: string
                            type: object
                          serviceRef:
                            description: Select a Service.
                            properties:
                              apiVersion:
                                description: API version of the referent.
                                type: string
                              fieldPath:
                                description: 'If referring to a piece of an object instead
                                  of an entire object, this string should contain a valid
                                  JSON/Go field access statement, such as desiredState.manifest.containers[2].
                                  For example, if the object reference is to a container
                                  within a pod, this would take on a value like: "spec.containers{name}"
                                  (where "name" refers to the name of the container that
                                  triggered the event) or if no container name is specified
                                  "spec.containers[2]" (container with index 2 in this
                                  pod). This syntax is chosen only to have some well-defined
                                  way of referencing a part of an object. TODO: this design
                                  is not final and this field is subject to change in
                                  the future.'
                                type: string
                              kind:
                                description: 'Kind of the referent. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
                                type: string
                              name:
                                description: 'Name of the referent. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names'
                                type: string
                              namespace:
                                description: 'Namespace of the referent. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/'
                                type: string
                              path:
                                description: The optional HTTP path.
                                type: string
                              port:
                                description: The optional port to select.
                                format: int32
                                type: integer
                              protocol:
                                description: Protocol for the service
                                type: string
                              resourceVersion:
                                description: 'Specific resourceVersion to which this reference
                                  is made, if any. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#concurrency-control-and-consistency'
                                type: string
                              uid:
                                description: 'UID of the referent. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#uids'
                                type: string
                            type: object
                          type:
                            description: Type of source.
                            type: string
                        type: object
                    type: object
                  type: array
                selector:
                  description: 'Selector is a label query over kinds that created by the
                    application. It must match the component objects'' labels. More info:
                    https://kubernetes.io/docs/concepts/overview/working-with-objects/labels/#label-selectors'
                  properties:
                    matchExpressions:
                      description: matchExpressions is a list of label selector requirements.
                        The requirements are ANDed.
                      items:
                        description: A label selector requirement is a selector that contains
                          values, a key, and an operator that relates the key and values.
                        properties:
                          key:
                            description: key is the label key that the selector applies
                              to.
                            type: string
                          operator:
                            description: operator represents a key's relationship to a
                              set of values. Valid operators are In, NotIn, Exists and
                              DoesNotExist.
                            type: string
                          values:
                            description: values is an array of string values. If the operator
                              is In or NotIn, the values array must be non-empty. If the
                              operator is Exists or DoesNotExist, the values array must
                              be empty. This array is replaced during a strategic merge
                              patch.
                            items:
                              type: string
                            type: array
                        required:
                        - key
                        - operator
                        type: object
                      type: array
                    matchLabels:
                      additionalProperties:
                        type: string
                      description: matchLabels is a map of {key,value} pairs. A single
                        {key,value} in the matchLabels map is equivalent to an element
                        of matchExpressions, whose key field is "key", the operator is
                        "In", and the values array contains only "value". The requirements
                        are ANDed.
                      type: object
                  type: object
              type: object
            status:
              description: ApplicationStatus defines controller's the observed state of
                Application
              properties:
                components:
                  description: Object status array for all matching objects
                  items:
                    description: ObjectStatus is a generic status holder for objects
                    properties:
                      group:
                        description: Object group
                        type: string
                      kind:
                        description: Kind of object
                        type: string
                      link:
                        description: Link to object
                        type: string
                      name:
                        description: Name of object
                        type: string
                      status:
                        description: 'Status. Values: InProgress, Ready, Unknown'
                        type: string
                    type: object
                  type: array
                componentsReady:
                  description: 'ComponentsReady: status of the components in the format
                    ready/total'
                  type: string
                conditions:
                  description: Conditions represents the latest state of the object
                  items:
                    description: Condition describes the state of an object at a certain
                      point.
                    properties:
                      lastTransitionTime:
                        description: Last time the condition transitioned from one status
                          to another.
                        format: date-time
                        type: string
                      lastUpdateTime:
                        description: Last time the condition was probed
                        format: date-time
                        type: string
                      message:
                        description: A human readable message indicating details about
                          the transition.
                        type: string
                      reason:
                        description: The reason for the condition's last transition.
                        type: string
                      status:
                        description: Status of the condition, one of True, False, Unknown.
                        type: string
                      type:
                        description: Type of condition.
                        type: string
                    required:
                    - status
                    - type
                    type: object
                  type: array
                observedGeneration:
                  description: ObservedGeneration is the most recent generation observed.
                    It corresponds to the Object's generation, which is updated on mutation
                    by the API Server.
                  format: int64
                  type: integer
              type: object
          type: object
      version: v1beta1
      versions:
      - name: v1beta1
        served: true
        storage: true
    status:
      acceptedNames:
        kind: ""
        plural: ""
      conditions: []
      storedVersions: []

    ---
    apiVersion: apiextensions.k8s.io/v1beta1
    kind: CustomResourceDefinition
    metadata:
      annotations:
        controller-gen.kubebuilder.io/version: v0.2.9
      name: atlasclusters.atlas.dellemc.com
      labels:
        app.kubernetes.io/name: atlas-operator
        helm.sh/chart: atlas-operator
        app.kubernetes.io/component: atlas-operator
        app.kubernetes.io/part-of: atlas-operator
        app.kubernetes.io/managed-by: nautilus
    spec:
      additionalPrinterColumns:
      - JSONPath: .spec.image.tag
        name: TAG
        type: string
      - JSONPath: .status.replicas
        description: The number of Atlas replicas in the cluster
        name: REPLICAS
        type: integer
      - JSONPath: .status.readyReplicas
        description: The number of Atlas replicas ready to serve
        name: READYREPLICAS
        type: integer
      group: atlas.dellemc.com
      names:
        kind: AtlasCluster
        listKind: AtlasClusterList
        plural: atlasclusters
        shortNames:
        - atlas
        - ac
        singular: atlascluster
      scope: Namespaced
      subresources:
        status: {}
      validation:
        openAPIV3Schema:
          description: AtlasCluster is the Schema for the atlasclusters API must add subresource
            to make status editable
          properties:
            apiVersion:
              description: 'APIVersion defines the versioned schema of this representation
                of an object. Servers should convert recognized schemas to the latest
                internal value, and may reject unrecognized values. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#resources'
              type: string
            kind:
              description: 'Kind is a string value representing the REST resource this
                object represents. Servers may infer this from the endpoint the client
                submits requests to. Cannot be updated. In CamelCase. More info: https://git.k8s.io/community/contributors/devel/sig-architecture/api-conventions.md#types-kinds'
              type: string
            metadata:
              type: object
            spec:
              description: AtlasClusterSpec defines the desired state of AtlasCluster
              properties:
                disableReconciliation:
                  description: Disable automatic reconciliation for the AtlasCluster
                  type: boolean
                image:
                  description: Container image
                  properties:
                    pullPolicy:
                      description: PullPolicy describes a policy for if/when to pull a
                        container image
                      type: string
                    repository:
                      type: string
                    tag:
                      type: string
                  type: object
                imagePullSecret:
                  description: Optional reference to a secret in the same namespace to
                    use when pulling images from registries
                  type: string
                labels:
                  additionalProperties:
                    type: string
                  description: Labels to attach to pods the operator creates for cluster.
                  type: object
                persistence:
                  description: Persistence is the configuration for persisting the Atlas
                    state on Volumes
                  properties:
                    annotations:
                      additionalProperties:
                        type: string
                      type: object
                    reclaimPolicy:
                      type: string
                    spec:
                      description: PersistentVolumeClaimSpec describes the common attributes
                        of storage devices and allows a Source for provider-specific attributes
                      properties:
                        accessModes:
                          description: 'AccessModes contains the desired access modes
                            the volume should have. More info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#access-modes-1'
                          items:
                            type: string
                          type: array
                        dataSource:
                          description: 'This field can be used to specify either: * An
                            existing VolumeSnapshot object (snapshot.storage.k8s.io/VolumeSnapshot)
                            * An existing PVC (PersistentVolumeClaim) * An existing custom
                            resource that implements data population (Alpha) In order
                            to use custom resource types that implement data population,
                            the AnyVolumeDataSource feature gate must be enabled. If the
                            provisioner or an external controller can support the specified
                            data source, it will create a new volume based on the contents
                            of the specified data source.'
                          properties:
                            apiGroup:
                              description: APIGroup is the group for the resource being
                                referenced. If APIGroup is not specified, the specified
                                Kind must be in the core API group. For any other third-party
                                types, APIGroup is required.
                              type: string
                            kind:
                              description: Kind is the type of resource being referenced
                              type: string
                            name:
                              description: Name is the name of resource being referenced
                              type: string
                          required:
                          - kind
                          - name
                          type: object
                        resources:
                          description: 'Resources represents the minimum resources the
                            volume should have. More info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#resources'
                          properties:
                            limits:
                              additionalProperties:
                                anyOf:
                                - type: integer
                                - type: string
                                pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                                x-kubernetes-int-or-string: true
                              description: 'Limits describes the maximum amount of compute
                                resources allowed. More info: https://kubernetes.io/docs/concepts/configuration/manage-compute-resources-container/'
                              type: object
                            requests:
                              additionalProperties:
                                anyOf:
                                - type: integer
                                - type: string
                                pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                                x-kubernetes-int-or-string: true
                              description: 'Requests describes the minimum amount of compute
                                resources required. If Requests is omitted for a container,
                                it defaults to Limits if that is explicitly specified,
                                otherwise to an implementation-defined value. More info:
                                https://kubernetes.io/docs/concepts/configuration/manage-compute-resources-container/'
                              type: object
                          type: object
                        selector:
                          description: A label query over volumes to consider for binding.
                          properties:
                            matchExpressions:
                              description: matchExpressions is a list of label selector
                                requirements. The requirements are ANDed.
                              items:
                                description: A label selector requirement is a selector
                                  that contains values, a key, and an operator that relates
                                  the key and values.
                                properties:
                                  key:
                                    description: key is the label key that the selector
                                      applies to.
                                    type: string
                                  operator:
                                    description: operator represents a key's relationship
                                      to a set of values. Valid operators are In, NotIn,
                                      Exists and DoesNotExist.
                                    type: string
                                  values:
                                    description: values is an array of string values.
                                      If the operator is In or NotIn, the values array
                                      must be non-empty. If the operator is Exists or
                                      DoesNotExist, the values array must be empty. This
                                      array is replaced during a strategic merge patch.
                                    items:
                                      type: string
                                    type: array
                                required:
                                - key
                                - operator
                                type: object
                              type: array
                            matchLabels:
                              additionalProperties:
                                type: string
                              description: matchLabels is a map of {key,value} pairs.
                                A single {key,value} in the matchLabels map is equivalent
                                to an element of matchExpressions, whose key field is
                                "key", the operator is "In", and the values array contains
                                only "value". The requirements are ANDed.
                              type: object
                          type: object
                        storageClassName:
                          description: 'Name of the StorageClass required by the claim.
                            More info: https://kubernetes.io/docs/concepts/storage/persistent-volumes#class-1'
                          type: string
                        volumeMode:
                          description: volumeMode defines what type of volume is required
                            by the claim. Value of Filesystem is implied when not included
                            in claim spec.
                          type: string
                        volumeName:
                          description: VolumeName is the binding reference to the PersistentVolume
                            backing this claim.
                          type: string
                      type: object
                  type: object
                pod:
                  description: pod properties
                  properties:
                    affinity:
                      description: The scheduling constraints on pods.
                      properties:
                        nodeAffinity:
                          description: Describes node affinity scheduling rules for the
                            pod.
                          properties:
                            preferredDuringSchedulingIgnoredDuringExecution:
                              description: The scheduler will prefer to schedule pods
                                to nodes that satisfy the affinity expressions specified
                                by this field, but it may choose a node that violates
                                one or more of the expressions. The node that is most
                                preferred is the one with the greatest sum of weights,
                                i.e. for each node that meets all of the scheduling requirements
                                (resource request, requiredDuringScheduling affinity expressions,
                                etc.), compute a sum by iterating through the elements
                                of this field and adding "weight" to the sum if the node
                                matches the corresponding matchExpressions; the node(s)
                                with the highest sum are the most preferred.
                              items:
                                description: An empty preferred scheduling term matches
                                  all objects with implicit weight 0 (i.e. it's a no-op).
                                  A null preferred scheduling term matches no objects
                                  (i.e. is also a no-op).
                                properties:
                                  preference:
                                    description: A node selector term, associated with
                                      the corresponding weight.
                                    properties:
                                      matchExpressions:
                                        description: A list of node selector requirements
                                          by node's labels.
                                        items:
                                          description: A node selector requirement is
                                            a selector that contains values, a key, and
                                            an operator that relates the key and values.
                                          properties:
                                            key:
                                              description: The label key that the selector
                                                applies to.
                                              type: string
                                            operator:
                                              description: Represents a key's relationship
                                                to a set of values. Valid operators are
                                                In, NotIn, Exists, DoesNotExist. Gt, and
                                                Lt.
                                              type: string
                                            values:
                                              description: An array of string values.
                                                If the operator is In or NotIn, the values
                                                array must be non-empty. If the operator
                                                is Exists or DoesNotExist, the values
                                                array must be empty. If the operator is
                                                Gt or Lt, the values array must have a
                                                single element, which will be interpreted
                                                as an integer. This array is replaced
                                                during a strategic merge patch.
                                              items:
                                                type: string
                                              type: array
                                          required:
                                          - key
                                          - operator
                                          type: object
                                        type: array
                                      matchFields:
                                        description: A list of node selector requirements
                                          by node's fields.
                                        items:
                                          description: A node selector requirement is
                                            a selector that contains values, a key, and
                                            an operator that relates the key and values.
                                          properties:
                                            key:
                                              description: The label key that the selector
                                                applies to.
                                              type: string
                                            operator:
                                              description: Represents a key's relationship
                                                to a set of values. Valid operators are
                                                In, NotIn, Exists, DoesNotExist. Gt, and
                                                Lt.
                                              type: string
                                            values:
                                              description: An array of string values.
                                                If the operator is In or NotIn, the values
                                                array must be non-empty. If the operator
                                                is Exists or DoesNotExist, the values
                                                array must be empty. If the operator is
                                                Gt or Lt, the values array must have a
                                                single element, which will be interpreted
                                                as an integer. This array is replaced
                                                during a strategic merge patch.
                                              items:
                                                type: string
                                              type: array
                                          required:
                                          - key
                                          - operator
                                          type: object
                                        type: array
                                    type: object
                                  weight:
                                    description: Weight associated with matching the corresponding
                                      nodeSelectorTerm, in the range 1-100.
                                    format: int32
                                    type: integer
                                required:
                                - preference
                                - weight
                                type: object
                              type: array
                            requiredDuringSchedulingIgnoredDuringExecution:
                              description: If the affinity requirements specified by this
                                field are not met at scheduling time, the pod will not
                                be scheduled onto the node. If the affinity requirements
                                specified by this field cease to be met at some point
                                during pod execution (e.g. due to an update), the system
                                may or may not try to eventually evict the pod from its
                                node.
                              properties:
                                nodeSelectorTerms:
                                  description: Required. A list of node selector terms.
                                    The terms are ORed.
                                  items:
                                    description: A null or empty node selector term matches
                                      no objects. The requirements of them are ANDed.
                                      The TopologySelectorTerm type implements a subset
                                      of the NodeSelectorTerm.
                                    properties:
                                      matchExpressions:
                                        description: A list of node selector requirements
                                          by node's labels.
                                        items:
                                          description: A node selector requirement is
                                            a selector that contains values, a key, and
                                            an operator that relates the key and values.
                                          properties:
                                            key:
                                              description: The label key that the selector
                                                applies to.
                                              type: string
                                            operator:
                                              description: Represents a key's relationship
                                                to a set of values. Valid operators are
                                                In, NotIn, Exists, DoesNotExist. Gt, and
                                                Lt.
                                              type: string
                                            values:
                                              description: An array of string values.
                                                If the operator is In or NotIn, the values
                                                array must be non-empty. If the operator
                                                is Exists or DoesNotExist, the values
                                                array must be empty. If the operator is
                                                Gt or Lt, the values array must have a
                                                single element, which will be interpreted
                                                as an integer. This array is replaced
                                                during a strategic merge patch.
                                              items:
                                                type: string
                                              type: array
                                          required:
                                          - key
                                          - operator
                                          type: object
                                        type: array
                                      matchFields:
                                        description: A list of node selector requirements
                                          by node's fields.
                                        items:
                                          description: A node selector requirement is
                                            a selector that contains values, a key, and
                                            an operator that relates the key and values.
                                          properties:
                                            key:
                                              description: The label key that the selector
                                                applies to.
                                              type: string
                                            operator:
                                              description: Represents a key's relationship
                                                to a set of values. Valid operators are
                                                In, NotIn, Exists, DoesNotExist. Gt, and
                                                Lt.
                                              type: string
                                            values:
                                              description: An array of string values.
                                                If the operator is In or NotIn, the values
                                                array must be non-empty. If the operator
                                                is Exists or DoesNotExist, the values
                                                array must be empty. If the operator is
                                                Gt or Lt, the values array must have a
                                                single element, which will be interpreted
                                                as an integer. This array is replaced
                                                during a strategic merge patch.
                                              items:
                                                type: string
                                              type: array
                                          required:
                                          - key
                                          - operator
                                          type: object
                                        type: array
                                    type: object
                                  type: array
                              required:
                              - nodeSelectorTerms
                              type: object
                          type: object
                        podAffinity:
                          description: Describes pod affinity scheduling rules (e.g. co-locate
                            this pod in the same node, zone, etc. as some other pod(s)).
                          properties:
                            preferredDuringSchedulingIgnoredDuringExecution:
                              description: The scheduler will prefer to schedule pods
                                to nodes that satisfy the affinity expressions specified
                                by this field, but it may choose a node that violates
                                one or more of the expressions. The node that is most
                                preferred is the one with the greatest sum of weights,
                                i.e. for each node that meets all of the scheduling requirements
                                (resource request, requiredDuringScheduling affinity expressions,
                                etc.), compute a sum by iterating through the elements
                                of this field and adding "weight" to the sum if the node
                                has pods which matches the corresponding podAffinityTerm;
                                the node(s) with the highest sum are the most preferred.
                              items:
                                description: The weights of all of the matched WeightedPodAffinityTerm
                                  fields are added per-node to find the most preferred
                                  node(s)
                                properties:
                                  podAffinityTerm:
                                    description: Required. A pod affinity term, associated
                                      with the corresponding weight.
                                    properties:
                                      labelSelector:
                                        description: A label query over a set of resources,
                                          in this case pods.
                                        properties:
                                          matchExpressions:
                                            description: matchExpressions is a list of
                                              label selector requirements. The requirements
                                              are ANDed.
                                            items:
                                              description: A label selector requirement
                                                is a selector that contains values, a
                                                key, and an operator that relates the
                                                key and values.
                                              properties:
                                                key:
                                                  description: key is the label key that
                                                    the selector applies to.
                                                  type: string
                                                operator:
                                                  description: operator represents a key's
                                                    relationship to a set of values. Valid
                                                    operators are In, NotIn, Exists and
                                                    DoesNotExist.
                                                  type: string
                                                values:
                                                  description: values is an array of string
                                                    values. If the operator is In or NotIn,
                                                    the values array must be non-empty.
                                                    If the operator is Exists or DoesNotExist,
                                                    the values array must be empty. This
                                                    array is replaced during a strategic
                                                    merge patch.
                                                  items:
                                                    type: string
                                                  type: array
                                              required:
                                              - key
                                              - operator
                                              type: object
                                            type: array
                                          matchLabels:
                                            additionalProperties:
                                              type: string
                                            description: matchLabels is a map of {key,value}
                                              pairs. A single {key,value} in the matchLabels
                                              map is equivalent to an element of matchExpressions,
                                              whose key field is "key", the operator is
                                              "In", and the values array contains only
                                              "value". The requirements are ANDed.
                                            type: object
                                        type: object
                                      namespaces:
                                        description: namespaces specifies which namespaces
                                          the labelSelector applies to (matches against);
                                          null or empty list means "this pod's namespace"
                                        items:
                                          type: string
                                        type: array
                                      topologyKey:
                                        description: This pod should be co-located (affinity)
                                          or not co-located (anti-affinity) with the pods
                                          matching the labelSelector in the specified
                                          namespaces, where co-located is defined as running
                                          on a node whose value of the label with key
                                          topologyKey matches that of any node on which
                                          any of the selected pods is running. Empty topologyKey
                                          is not allowed.
                                        type: string
                                    required:
                                    - topologyKey
                                    type: object
                                  weight:
                                    description: weight associated with matching the corresponding
                                      podAffinityTerm, in the range 1-100.
                                    format: int32
                                    type: integer
                                required:
                                - podAffinityTerm
                                - weight
                                type: object
                              type: array
                            requiredDuringSchedulingIgnoredDuringExecution:
                              description: If the affinity requirements specified by this
                                field are not met at scheduling time, the pod will not
                                be scheduled onto the node. If the affinity requirements
                                specified by this field cease to be met at some point
                                during pod execution (e.g. due to a pod label update),
                                the system may or may not try to eventually evict the
                                pod from its node. When there are multiple elements, the
                                lists of nodes corresponding to each podAffinityTerm are
                                intersected, i.e. all terms must be satisfied.
                              items:
                                description: Defines a set of pods (namely those matching
                                  the labelSelector relative to the given namespace(s))
                                  that this pod should be co-located (affinity) or not
                                  co-located (anti-affinity) with, where co-located is
                                  defined as running on a node whose value of the label
                                  with key <topologyKey> matches that of any node on which
                                  a pod of the set of pods is running
                                properties:
                                  labelSelector:
                                    description: A label query over a set of resources,
                                      in this case pods.
                                    properties:
                                      matchExpressions:
                                        description: matchExpressions is a list of label
                                          selector requirements. The requirements are
                                          ANDed.
                                        items:
                                          description: A label selector requirement is
                                            a selector that contains values, a key, and
                                            an operator that relates the key and values.
                                          properties:
                                            key:
                                              description: key is the label key that the
                                                selector applies to.
                                              type: string
                                            operator:
                                              description: operator represents a key's
                                                relationship to a set of values. Valid
                                                operators are In, NotIn, Exists and DoesNotExist.
                                              type: string
                                            values:
                                              description: values is an array of string
                                                values. If the operator is In or NotIn,
                                                the values array must be non-empty. If
                                                the operator is Exists or DoesNotExist,
                                                the values array must be empty. This array
                                                is replaced during a strategic merge patch.
                                              items:
                                                type: string
                                              type: array
                                          required:
                                          - key
                                          - operator
                                          type: object
                                        type: array
                                      matchLabels:
                                        additionalProperties:
                                          type: string
                                        description: matchLabels is a map of {key,value}
                                          pairs. A single {key,value} in the matchLabels
                                          map is equivalent to an element of matchExpressions,
                                          whose key field is "key", the operator is "In",
                                          and the values array contains only "value".
                                          The requirements are ANDed.
                                        type: object
                                    type: object
                                  namespaces:
                                    description: namespaces specifies which namespaces
                                      the labelSelector applies to (matches against);
                                      null or empty list means "this pod's namespace"
                                    items:
                                      type: string
                                    type: array
                                  topologyKey:
                                    description: This pod should be co-located (affinity)
                                      or not co-located (anti-affinity) with the pods
                                      matching the labelSelector in the specified namespaces,
                                      where co-located is defined as running on a node
                                      whose value of the label with key topologyKey matches
                                      that of any node on which any of the selected pods
                                      is running. Empty topologyKey is not allowed.
                                    type: string
                                required:
                                - topologyKey
                                type: object
                              type: array
                          type: object
                        podAntiAffinity:
                          description: Describes pod anti-affinity scheduling rules (e.g.
                            avoid putting this pod in the same node, zone, etc. as some
                            other pod(s)).
                          properties:
                            preferredDuringSchedulingIgnoredDuringExecution:
                              description: The scheduler will prefer to schedule pods
                                to nodes that satisfy the anti-affinity expressions specified
                                by this field, but it may choose a node that violates
                                one or more of the expressions. The node that is most
                                preferred is the one with the greatest sum of weights,
                                i.e. for each node that meets all of the scheduling requirements
                                (resource request, requiredDuringScheduling anti-affinity
                                expressions, etc.), compute a sum by iterating through
                                the elements of this field and adding "weight" to the
                                sum if the node has pods which matches the corresponding
                                podAffinityTerm; the node(s) with the highest sum are
                                the most preferred.
                              items:
                                description: The weights of all of the matched WeightedPodAffinityTerm
                                  fields are added per-node to find the most preferred
                                  node(s)
                                properties:
                                  podAffinityTerm:
                                    description: Required. A pod affinity term, associated
                                      with the corresponding weight.
                                    properties:
                                      labelSelector:
                                        description: A label query over a set of resources,
                                          in this case pods.
                                        properties:
                                          matchExpressions:
                                            description: matchExpressions is a list of
                                              label selector requirements. The requirements
                                              are ANDed.
                                            items:
                                              description: A label selector requirement
                                                is a selector that contains values, a
                                                key, and an operator that relates the
                                                key and values.
                                              properties:
                                                key:
                                                  description: key is the label key that
                                                    the selector applies to.
                                                  type: string
                                                operator:
                                                  description: operator represents a key's
                                                    relationship to a set of values. Valid
                                                    operators are In, NotIn, Exists and
                                                    DoesNotExist.
                                                  type: string
                                                values:
                                                  description: values is an array of string
                                                    values. If the operator is In or NotIn,
                                                    the values array must be non-empty.
                                                    If the operator is Exists or DoesNotExist,
                                                    the values array must be empty. This
                                                    array is replaced during a strategic
                                                    merge patch.
                                                  items:
                                                    type: string
                                                  type: array
                                              required:
                                              - key
                                              - operator
                                              type: object
                                            type: array
                                          matchLabels:
                                            additionalProperties:
                                              type: string
                                            description: matchLabels is a map of {key,value}
                                              pairs. A single {key,value} in the matchLabels
                                              map is equivalent to an element of matchExpressions,
                                              whose key field is "key", the operator is
                                              "In", and the values array contains only
                                              "value". The requirements are ANDed.
                                            type: object
                                        type: object
                                      namespaces:
                                        description: namespaces specifies which namespaces
                                          the labelSelector applies to (matches against);
                                          null or empty list means "this pod's namespace"
                                        items:
                                          type: string
                                        type: array
                                      topologyKey:
                                        description: This pod should be co-located (affinity)
                                          or not co-located (anti-affinity) with the pods
                                          matching the labelSelector in the specified
                                          namespaces, where co-located is defined as running
                                          on a node whose value of the label with key
                                          topologyKey matches that of any node on which
                                          any of the selected pods is running. Empty topologyKey
                                          is not allowed.
                                        type: string
                                    required:
                                    - topologyKey
                                    type: object
                                  weight:
                                    description: weight associated with matching the corresponding
                                      podAffinityTerm, in the range 1-100.
                                    format: int32
                                    type: integer
                                required:
                                - podAffinityTerm
                                - weight
                                type: object
                              type: array
                            requiredDuringSchedulingIgnoredDuringExecution:
                              description: If the anti-affinity requirements specified
                                by this field are not met at scheduling time, the pod
                                will not be scheduled onto the node. If the anti-affinity
                                requirements specified by this field cease to be met at
                                some point during pod execution (e.g. due to a pod label
                                update), the system may or may not try to eventually evict
                                the pod from its node. When there are multiple elements,
                                the lists of nodes corresponding to each podAffinityTerm
                                are intersected, i.e. all terms must be satisfied.
                              items:
                                description: Defines a set of pods (namely those matching
                                  the labelSelector relative to the given namespace(s))
                                  that this pod should be co-located (affinity) or not
                                  co-located (anti-affinity) with, where co-located is
                                  defined as running on a node whose value of the label
                                  with key <topologyKey> matches that of any node on which
                                  a pod of the set of pods is running
                                properties:
                                  labelSelector:
                                    description: A label query over a set of resources,
                                      in this case pods.
                                    properties:
                                      matchExpressions:
                                        description: matchExpressions is a list of label
                                          selector requirements. The requirements are
                                          ANDed.
                                        items:
                                          description: A label selector requirement is
                                            a selector that contains values, a key, and
                                            an operator that relates the key and values.
                                          properties:
                                            key:
                                              description: key is the label key that the
                                                selector applies to.
                                              type: string
                                            operator:
                                              description: operator represents a key's
                                                relationship to a set of values. Valid
                                                operators are In, NotIn, Exists and DoesNotExist.
                                              type: string
                                            values:
                                              description: values is an array of string
                                                values. If the operator is In or NotIn,
                                                the values array must be non-empty. If
                                                the operator is Exists or DoesNotExist,
                                                the values array must be empty. This array
                                                is replaced during a strategic merge patch.
                                              items:
                                                type: string
                                              type: array
                                          required:
                                          - key
                                          - operator
                                          type: object
                                        type: array
                                      matchLabels:
                                        additionalProperties:
                                          type: string
                                        description: matchLabels is a map of {key,value}
                                          pairs. A single {key,value} in the matchLabels
                                          map is equivalent to an element of matchExpressions,
                                          whose key field is "key", the operator is "In",
                                          and the values array contains only "value".
                                          The requirements are ANDed.
                                        type: object
                                    type: object
                                  namespaces:
                                    description: namespaces specifies which namespaces
                                      the labelSelector applies to (matches against);
                                      null or empty list means "this pod's namespace"
                                    items:
                                      type: string
                                    type: array
                                  topologyKey:
                                    description: This pod should be co-located (affinity)
                                      or not co-located (anti-affinity) with the pods
                                      matching the labelSelector in the specified namespaces,
                                      where co-located is defined as running on a node
                                      whose value of the label with key topologyKey matches
                                      that of any node on which any of the selected pods
                                      is running. Empty topologyKey is not allowed.
                                    type: string
                                required:
                                - topologyKey
                                type: object
                              type: array
                          type: object
                      type: object
                    annotations:
                      additionalProperties:
                        type: string
                      description: Annotations to set on the pods.
                      type: object
                    env:
                      description: List of environment variables to set in the container.
                      items:
                        description: EnvVar represents an environment variable present
                          in a Container.
                        properties:
                          name:
                            description: Name of the environment variable. Must be a C_IDENTIFIER.
                            type: string
                          value:
                            description: 'Variable references $(VAR_NAME) are expanded
                              using the previous defined environment variables in the
                              container and any service environment variables. If a variable
                              cannot be resolved, the reference in the input string will
                              be unchanged. The $(VAR_NAME) syntax can be escaped with
                              a double $$, ie: $$(VAR_NAME). Escaped references will never
                              be expanded, regardless of whether the variable exists or
                              not. Defaults to "".'
                            type: string
                          valueFrom:
                            description: Source for the environment variable's value.
                              Cannot be used if value is not empty.
                            properties:
                              configMapKeyRef:
                                description: Selects a key of a ConfigMap.
                                properties:
                                  key:
                                    description: The key to select.
                                    type: string
                                  name:
                                    description: 'Name of the referent. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names
                                      TODO: Add other useful fields. apiVersion, kind,
                                      uid?'
                                    type: string
                                  optional:
                                    description: Specify whether the ConfigMap or its
                                      key must be defined
                                    type: boolean
                                required:
                                - key
                                type: object
                              fieldRef:
                                description: 'Selects a field of the pod: supports metadata.name,
                                  metadata.namespace, `metadata.labels[''<KEY>'']`, `metadata.annotations[''<KEY>'']`,
                                  spec.nodeName, spec.serviceAccountName, status.hostIP,
                                  status.podIP, status.podIPs.'
                                properties:
                                  apiVersion:
                                    description: Version of the schema the FieldPath is
                                      written in terms of, defaults to "v1".
                                    type: string
                                  fieldPath:
                                    description: Path of the field to select in the specified
                                      API version.
                                    type: string
                                required:
                                - fieldPath
                                type: object
                              resourceFieldRef:
                                description: 'Selects a resource of the container: only
                                  resources limits and requests (limits.cpu, limits.memory,
                                  limits.ephemeral-storage, requests.cpu, requests.memory
                                  and requests.ephemeral-storage) are currently supported.'
                                properties:
                                  containerName:
                                    description: 'Container name: required for volumes,
                                      optional for env vars'
                                    type: string
                                  divisor:
                                    anyOf:
                                    - type: integer
                                    - type: string
                                    description: Specifies the output format of the exposed
                                      resources, defaults to "1"
                                    pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                                    x-kubernetes-int-or-string: true
                                  resource:
                                    description: 'Required: resource to select'
                                    type: string
                                required:
                                - resource
                                type: object
                              secretKeyRef:
                                description: Selects a key of a secret in the pod's namespace
                                properties:
                                  key:
                                    description: The key of the secret to select from.  Must
                                      be a valid secret key.
                                    type: string
                                  name:
                                    description: 'Name of the referent. More info: https://kubernetes.io/docs/concepts/overview/working-with-objects/names/#names
                                      TODO: Add other useful fields. apiVersion, kind,
                                      uid?'
                                    type: string
                                  optional:
                                    description: Specify whether the Secret or its key
                                      must be defined
                                    type: boolean
                                required:
                                - key
                                type: object
                            type: object
                        required:
                        - name
                        type: object
                      type: array
                    nodeSelector:
                      additionalProperties:
                        type: string
                      description: NodeSelector specifies a map of key-value pairs. For
                        the pod to be eligible to run on a node, the node must have each
                        of the indicated key-value pairs as labels.
                      type: object
                    tolerations:
                      description: Tolerations specifies the pod's tolerations.
                      items:
                        description: The pod this Toleration is attached to tolerates
                          any taint that matches the triple <key,value,effect> using the
                          matching operator <operator>.
                        properties:
                          effect:
                            description: Effect indicates the taint effect to match. Empty
                              means match all taint effects. When specified, allowed values
                              are NoSchedule, PreferNoSchedule and NoExecute.
                            type: string
                          key:
                            description: Key is the taint key that the toleration applies
                              to. Empty means match all taint keys. If the key is empty,
                              operator must be Exists; this combination means to match
                              all values and all keys.
                            type: string
                          operator:
                            description: Operator represents a key's relationship to the
                              value. Valid operators are Exists and Equal. Defaults to
                              Equal. Exists is equivalent to wildcard for value, so that
                              a pod can tolerate all taints of a particular category.
                            type: string
                          tolerationSeconds:
                            description: TolerationSeconds represents the period of time
                              the toleration (which must be of effect NoExecute, otherwise
                              this field is ignored) tolerates the taint. By default,
                              it is not set, which means tolerate the taint forever (do
                              not evict). Zero and negative values will be treated as
                              0 (evict immediately) by the system.
                            format: int64
                            type: integer
                          value:
                            description: Value is the taint value the toleration matches
                              to. If the operator is Exists, the value should be empty,
                              otherwise just a regular string.
                            type: string
                        type: object
                      type: array
                  type: object
                ports:
                  description: ports for atlas
                  items:
                    description: ContainerPort represents a network port in a single container.
                    properties:
                      containerPort:
                        description: Number of port to expose on the pod's IP address.
                          This must be a valid port number, 0 < x < 65536.
                        format: int32
                        type: integer
                      hostIP:
                        description: What host IP to bind the external port to.
                        type: string
                      hostPort:
                        description: Number of port to expose on the host. If specified,
                          this must be a valid port number, 0 < x < 65536. If HostNetwork
                          is specified, this must match ContainerPort. Most containers
                          do not need this.
                        format: int32
                        type: integer
                      name:
                        description: If specified, this must be an IANA_SVC_NAME and unique
                          within the pod. Each named port in a pod must have a unique
                          name. Name for the port that can be referred to by services.
                        type: string
                      protocol:
                        description: Protocol for port. Must be UDP, TCP, or SCTP. Defaults
                          to "TCP".
                        type: string
                    required:
                    - containerPort
                    type: object
                  type: array
                replicas:
                  description: Expected size of the cluster
                  format: int32
                  type: integer
                resources:
                  description: Compute Resources required by the Atlas container.
                  properties:
                    limits:
                      additionalProperties:
                        anyOf:
                        - type: integer
                        - type: string
                        pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                        x-kubernetes-int-or-string: true
                      description: 'Limits describes the maximum amount of compute resources
                        allowed. More info: https://kubernetes.io/docs/concepts/configuration/manage-compute-resources-container/'
                      type: object
                    requests:
                      additionalProperties:
                        anyOf:
                        - type: integer
                        - type: string
                        pattern: ^(\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))(([KMGTPE]i)|[numkMGTPE]|([eE](\+|-)?(([0-9]+(\.[0-9]*)?)|(\.[0-9]+))))?$
                        x-kubernetes-int-or-string: true
                      description: 'Requests describes the minimum amount of compute resources
                        required. If Requests is omitted for a container, it defaults
                        to Limits if that is explicitly specified, otherwise to an implementation-defined
                        value. More info: https://kubernetes.io/docs/concepts/configuration/manage-compute-resources-container/'
                      type: object
                  type: object
              type: object
            status:
              description: 'AtlasClusterStatus defines the observed state of AtlasCluster
                NOTE: status is not needed for now but might be handy with flex'
              properties:
                members:
                  properties:
                    ready:
                      items:
                        type: string
                      type: array
                    unready:
                      items:
                        type: string
                      type: array
                  type: object
                readyReplicas:
                  description: ReadyReplicas is the number of number of ready replicas
                    in the cluster
                  format: int32
                  type: integer
                replicas:
                  description: Replicas is the number of number of desired replicas in
                    the cluster
                  format: int32
                  type: integer
              required:
              - readyReplicas
              - replicas
              type: object
          type: object
      version: v1beta1
      versions:
      - name: v1beta1
        served: true
        storage: true
    status:
      acceptedNames:
        kind: ""
        plural: ""
      conditions: []
      storedVersions: []
    ---
    apiVersion: apiextensions.k8s.io/v1beta1
    kind: CustomResourceDefinition
    metadata:
      name: customercontacts.decks.ecs.dellemc.com
    spec:
      group: decks.ecs.dellemc.com
      names:
        kind: CustomerContact
        listKind: CustomerContactList
        plural: customercontacts
        singular: customercontact
      scope: Namespaced
      version: v1beta1
    ---
    apiVersion: apiextensions.k8s.io/v1beta1
    kind: CustomResourceDefinition
    metadata:
      name: ecsclusters.ecs.dellemc.com
      labels:
        app.kubernetes.io/name: objectscale-manager
        helm.sh/chart: objectscale-manager
        app.kubernetes.io/component: objectscale-operator
        app.kubernetes.io/part-of: objectscale-manager
        app.kubernetes.io/managed-by: nautilus
    spec:
      group: ecs.dellemc.com
      names:
        kind: ECSCluster
        listKind: ECSClusterList
        plural: ecsclusters
        singular: ecscluster
        shortNames:
        - ecs
        - ecs-cluster
      scope: Namespaced
      versions:
        - name: v1beta1
          served: true
          storage: true
      additionalPrinterColumns:
      - name: PHASE
        type: string
        description: The current phase of cluster operation
        JSONPath: .status.phase
      - name: READY COMPONENTS
        type: string
        description: A string display of the number of components ready
        JSONPath: .status.readyComponents
      - name: S3 ENDPOINT
        type: string
        description: The HTTPS endpoint for accessing the cluster via S3
        JSONPath: .status.endpoints.s3Secure
      - name: MGMT API
        type: string
        description: The HTTPS location for the management API
        JSONPath: .status.endpoints.managementAPI

    ---
    apiVersion: apiextensions.k8s.io/v1beta1
    kind: CustomResourceDefinition
    metadata:
      annotations:
        controller-gen.kubebuilder.io/version: v0.3.0
      creationTimestamp: null
      name: influxdbs.db.ecs.dellemc.com
    spec:
      group: db.ecs.dellemc.com
      names:
        kind: Influxdb
        listKind: InfluxdbList
        plural: influxdbs
        singular: influxdb
      scope: Namespaced
      subresources:
        status: {}
      version: v1
      versions:
      - name: v1
        served: true
        storage: true
    status:
      acceptedNames:
        kind: ""
        plural: ""
      conditions: []
      storedVersions: []
    ---
    apiVersion: apiextensions.k8s.io/v1beta1
    kind: CustomResourceDefinition
    metadata:
      name: licenses.decks.ecs.dellemc.com
    spec:
      group: decks.ecs.dellemc.com
      names:
        kind: License
        listKind: LicenseList
        plural: licenses
        singular: license
      scope: Namespaced
      version: v1beta1
    ---
    apiVersion: apiextensions.k8s.io/v1beta1
    kind: CustomResourceDefinition
    metadata:
      name: networkconnections.ecs.dellemc.com
      labels:
        app.kubernetes.io/name: objectscale-manager
        helm.sh/chart: objectscale-manager
        app.kubernetes.io/component: objectscale-operator
        app.kubernetes.io/part-of: objectscale-manager
        app.kubernetes.io/managed-by: nautilus
    spec:
      group: ecs.dellemc.com
      names:
        kind: NetworkConnection
        listKind: NetworkConnectionList
        plural: networkconnections
        singular: networkconnection
        shortNames:
        - tls
        - cert
        - connection
        - netcon
      scope: Namespaced
      versions:
      - name: v1beta1
        served: true
        storage: true
      additionalPrinterColumns:
      - name: PHASE
        type: string
        description: The current phase of cluster operation
        JSONPath: .status.phase
    ---
    apiVersion: apiextensions.k8s.io/v1beta1
    kind: CustomResourceDefinition
    metadata:
      name: notifiers.kahm.emcecs.github.com
    spec:
      group: kahm.emcecs.github.com
      names:
        kind: Notifier
        listKind: NotifierList
        plural: notifiers
        singular: notifier
      scope: Namespaced
      version: v1beta1
      additionalPrinterColumns:
      - name: READY
        type: string
        description: The current phase of cluster operation
        JSONPath: .status.ready
    ---
    apiVersion: apiextensions.k8s.io/v1beta1
    kind: CustomResourceDefinition
    metadata:
      name: srsgateways.decks.ecs.dellemc.com
    spec:
      group: decks.ecs.dellemc.com
      names:
        kind: SRSGateway
        listKind: SRSGatewayList
        plural: srsgateways
        singular: srsgateway
      scope: Namespaced
      version: v1beta1

    ---
    apiVersion: apiextensions.k8s.io/v1beta1
    kind: CustomResourceDefinition
    metadata:
      annotations:
        controller-gen.kubebuilder.io/version: v0.3.0
      creationTimestamp: null
      name: statefuldaemonsets.stateful.ecs.dellemc.com
    spec:
      group: stateful.ecs.dellemc.com
      names:
        kind: StatefulDaemonSet
        listKind: StatefulDaemonSetList
        plural: statefuldaemonsets
        singular: statefuldaemonset
      scope: Namespaced
      subresources:
        status: {}
      version: v1alpha1
      versions:
      - name: v1alpha1
        served: true
        storage: true
    status:
      acceptedNames:
        kind: ""
        plural: ""
      conditions: []
      storedVersions: []
    ---
    apiVersion: apiextensions.k8s.io/v1beta1
    kind: CustomResourceDefinition
    metadata:
      name: ecs-storagepolicies.ecs.dellemc.com
      labels:
        app.kubernetes.io/name: objectscale-manager
        helm.sh/chart: objectscale-manager
        app.kubernetes.io/component: objectscale-operator
        app.kubernetes.io/part-of: objectscale-manager
        app.kubernetes.io/managed-by: nautilus
    spec:
      group: ecs.dellemc.com
      names:
        kind: StoragePolicy
        listKind: StoragePolicyList
        plural: ecs-storagepolicies
        singular: ecs-storagepolicy
        shortNames:
          - ecssp
      scope: Namespaced
      versions:
        - name: v1beta1
          served: true
          storage: true
    ---
    apiVersion: apiextensions.k8s.io/v1beta1
    kind: CustomResourceDefinition
    metadata:
      name: storagetiers.ecs.dellemc.com
      labels:
        app.kubernetes.io/name: objectscale-manager
        helm.sh/chart: objectscale-manager
        app.kubernetes.io/component: objectscale-operator
        app.kubernetes.io/part-of: objectscale-manager
        app.kubernetes.io/managed-by: nautilus
    spec:
      group: ecs.dellemc.com
      names:
        kind: StorageTier
        listKind: StorageTierList
        plural: storagetiers
        singular: storagetier
        shortNames:
          - st
      scope: Namespaced
      versions:
        - name: v1beta1
          served: true
          storage: true
    ---
    apiVersion: apiextensions.k8s.io/v1beta1
    kind: CustomResourceDefinition
    metadata:
      name: supportassists.decks.ecs.dellemc.com
    spec:
      group: decks.ecs.dellemc.com
      names:
        kind: SupportAssist
        listKind: SupportAssistList
        plural: supportassists
        singular: supportassist
      scope: Namespaced
      versions:
        - name: v1beta1
          served: true
          storage: true
      additionalPrinterColumns:
      - name: PHASE
        type: string
        description: The current phase of SupportAssist
        JSONPath: .status.phase

    ---
    apiVersion: apiextensions.k8s.io/v1beta1
    kind: CustomResourceDefinition
    metadata:
      name: zookeeperclusters.zookeeper.pravega.io
    spec:
      group: zookeeper.pravega.io
      names:
        kind: ZookeeperCluster
        listKind: ZookeeperClusterList
        plural: zookeeperclusters
        singular: zookeepercluster
        shortNames:
        - zk
      additionalPrinterColumns:
      - name: Replicas
        type: integer
        description: The number of ZooKeeper servers in the ensemble
        JSONPath: .spec.replicas
      - name: Ready Replicas
        type: integer
        description: The number of ZooKeeper servers in the ensemble that are in a Ready state
        JSONPath: .status.readyReplicas
      - name: Version
        type: string
        description: The current Zookeeper version
        JSONPath: .status.currentVersion
      - name: Desired Version
        type: string
        description: The desired Zookeeper version
        JSONPath: .spec.image.tag
      - name: Internal Endpoint
        type: string
        description: Client endpoint internal to cluster network
        JSONPath: .status.internalClientEndpoint
      - name: External Endpoint
        type: string
        description: Client endpoint external to cluster network via LoadBalancer
        JSONPath: .status.externalClientEndpoint
      - name: Age
        type: date
        JSONPath: .metadata.creationTimestamp
      scope: Namespaced
      version: v1beta1
      subresources:
        status: {}
  objectscale-operator.yaml: |-
    ---
    # Source: objectscale-vsphere/templates/vsphere-plugin-network-policy.yaml
    apiVersion: networking.k8s.io/v1
    kind: NetworkPolicy
    metadata:
      name: objectscale-allow-all
      namespace: {{ .service.namespace }}
    spec:
      ingress:
        - {}
      podSelector: {}
      policyTypes:
        - Ingress
    ---
    # Source: objectscale-vsphere/charts/objectscale-portal/charts/objectscale-graphql/charts/helm-controller/templates/controller-rbac.yaml
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: install-controller
      namespace: {{ .service.namespace }}
      labels:
        app.kubernetes.io/name: objectscale-manager
        app.kubernetes.io/instance: vsphere-plugin
        app.kubernetes.io/managed-by: Helm
        app.kubernetes.io/version: 0.70.1
        app.kubernetes.io/component: objectscale-operator
        app.kubernetes.io/part-of: vsphere-plugin
        helm.sh/chart: helm-controller-0.70.1
        release: vsphere-plugin
        operator: objectscale-operator
        product: objectscale
    imagePullSecrets:
      - name: vsphere-docker-secret
    ---
    # Source: objectscale-vsphere/charts/objectscale-portal/charts/objectscale-graphql/templates/objecscale-api-rbac.yaml
    apiVersion: v1
    kind: ServiceAccount
    metadata:
      name: objectscale-api
      namespace: {{ .service.namespace }}
      labels:
        app.kubernetes.io/name: objectscale-manager
        app.kubernetes.io/instance: vsphere-plugin
        app.kubernetes.io/managed-by: Helm
        app.kubernetes.io/version: 0.70.1
        app.kubernetes.io/component: objectscale-graphql
        app.kubernetes.io/part-of: vsphere-plugin
        helm.sh/chart: objectscale-graphql-0.70.1
        release: vsphere-plugin
        operator: objectscale-operator
        product: objectscale
    imagePullSecrets:
      - name: vsphere-docker-secret
    ---
    # Source: objectscale-vsphere/templates/vsphere-plugin-secrets.yaml
    apiVersion: v1
    kind: Secret
    metadata:
      name: vsphere-docker-secret
      namespace: {{ .service.namespace }}
    data:
      .dockerconfigjson: {{printf "{\"auths\": {\"%s\": {\"auth\": \"%s\"}}}" .Values.registryName (printf "%s:%s" .Values.registryUsername .Values.registryPasswd | b64enc) | b64enc}}
    type: kubernetes.io/dockerconfigjson
    ---
    # Source: objectscale-vsphere/charts/objectscale-portal/charts/rsyslog-client/templates/rsyslog-client-config.yaml
    #
    # Copyright © [2020] Dell Inc. or its subsidiaries.
    # All Rights Reserved.
    #
    # This software contains the intellectual property of Dell Inc.
    # or is licensed to Dell Inc. from third parties. Use of this
    # software and the intellectual property contained therein is expressly
    # limited to the terms and conditions of the License Agreement under which
    # it is provided by or on behalf of Dell Inc. or its subsidiaries.
    #
    #

    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: vsphere-plugin-rsyslog-client-config
      # namespace is required for resources created by objectscale-vsphere
      namespace: {{ .service.namespace }}
      labels:
        app.kubernetes.io/name: vsphere-plugin-rsyslog-client
        app.kubernetes.io/instance: vsphere-plugin
        app.kubernetes.io/managed-by: Helm
        app.kubernetes.io/version: "0.54.0"
        app.kubernetes.io/part-of: vsphere-plugin
        helm.sh/chart: rsyslog-client-3.7.0-1164.08aefd2c
        release: vsphere-plugin
    data:
      rsyslog.conf.template: |+
        #### MODULES ####

        # input module: file
        module(load="imfile")

        #### GLOBAL DIRECTIVES ####

        #### RULES ####

        # input log files
        input(type="imfile"
              File="/var/log/*.log"
              Tag="vsphere-plugin"
              addMetadata="on"
              Ruleset="handle_multiple_logs"
              Facility="local0"
        )

        _STDOUT_CONF_

        ruleset(name="handle_multiple_logs") {
          # http://www.rsyslog.com/doc/v8-stable/rainerscript/functions.html
          # re_extract(expr, re, match, submatch, no-found)
          set $.suffix=re_extract($!metadata!filename, "(.*)/([^/]*)", 0, 2, "all.log");
          set $.pod_name=getenv("POD_NAME");
          call sendToLogserver
        }

        ruleset(name="handle_stdout_logs") {
          # http://www.rsyslog.com/doc/v8-stable/rainerscript/functions.html
          # re_extract(expr, re, match, submatch, no-found)
          set $.container_name=re_extract($!metadata!filename, "(.*)/([^/]*)/([^/]*)", 0, 2, "unknown_container");
          set $.log_name=re_extract($!metadata!filename, "(.*)/([^/]*)", 0, 2, "all.log");
          set $.suffix= $.container_name & ".stdout." & $.log_name;
          set $.pod_name=getenv("POD_NAME");
          call sendToLogserver
        }

        # output template
        template(name="FileFormat" type="string"
        string= "<%PRI%>%TIMESTAMP% %HOSTNAME% %syslogtag%__%$.pod_name%__%$.suffix%%msg:::sp-if-no-1st-sp%%msg:::drop-last-lf%\n"
                )

        ruleset(name="sendToLogserver") {
          action(type="omfwd"
              Target="_RSYSLOG_POD_NAME_.objectscale-manager-rsyslog.{{ .service.namespace }}.svc.cluster.local"
              Port="10514"
              Protocol="tcp"
              Template="FileFormat" )
        #    action.resumeRetryCount=100
        #    queue.type=linkedList queue.size=10000)
        }
      rsyslog_stdout.conf.template: |+
        input(type="imfile"
              File="_CONTAINER_DIR_/*.log"
              Tag="vsphere-plugin"
              addMetadata="on"
              Ruleset="handle_stdout_logs"
              Facility="local0"
        )
    ---
    # Source: objectscale-vsphere/charts/objectscale-portal/templates/objectscale-portal-configmap.yaml
    apiVersion: v1
    kind: ConfigMap
    metadata:
      name: objectscale-portal
      namespace: {{ .service.namespace }}
      labels:
        app.kubernetes.io/name: objectscale-manager
        app.kubernetes.io/instance: vsphere-plugin
        app.kubernetes.io/managed-by: Helm
        app.kubernetes.io/version: 0.70.2
        app.kubernetes.io/component: objectscale-portal
        app.kubernetes.io/part-of: vsphere-plugin
        helm.sh/chart: objectscale-portal-0.70.2
        release: vsphere-plugin
        operator: objectscale-operator
        product: objectscale
    data:
      upstream.conf: |
        upstream graphql {
            server objectscale-graphql:8080;
        }
      nginx.conf: |
        events {
            worker_connections  4096;  ## Default: 1024
        }

        http {
            include /etc/nginx/mime.types;
            include /conf/upstream.conf;
            map $request_method $decksname {
             default decks-support-store.{{ .service.namespace }}.svc.cluster.local;
            }
            map $request_method $decksport {
             default 7443;
            }
            server {
                resolver kube-dns.kube-system.svc.cluster.local;
                listen       4443;
                server_name  localhost;
                access_log /dev/stdout;
                error_log /dev/stdout;
                rewrite_log on;
                ssl on;
                ssl_protocols        TLSv1.2;
                ssl_ciphers          AES:!ADH;
                ssl_certificate /etc/nginx/ssl/tls.crt;
                ssl_certificate_key /etc/nginx/ssl/tls.key;
                location /wcp/login {
                    proxy_pass_request_headers on;
                    proxy_pass_request_body on;
                    proxy_pass https://kube-apiserver-authproxy-svc.kube-system.svc.cluster.local:8443/wcp/login;
                }
                location /rest/saml-hook {
                    proxy_pass_request_headers on;
                    proxy_pass_request_body on;
                    proxy_pass https://kube-apiserver-authproxy-svc.kube-system.svc.cluster.local:8443/wcp/vsphere-ui-saml-hook;
                }
                location /graphql {
                    proxy_pass http://graphql;
                }
                location /data {
                    proxy_pass https://$decksname:$decksport;
                }
                location ~* /grafana/[a-z0-9]([-a-z0-9]*[a-z0-9])?/[a-z0-9]([-a-z0-9]*[a-z0-9])? {
                    rewrite /grafana/([a-z0-9-]+)/([a-z0-9-]+)/(.*) /$3 break;
                    rewrite /grafana/([a-z0-9-]+)/([a-z0-9-]+) / break;
                    proxy_pass http://$2-grafana.$1.svc.cluster.local:3000;
                }
                location /platform {
                    default_type application/json;
                    return 200 '{"value":"VMware"}';
                }
                location /features {
                    return 200 '{"bucketsv2":false,"iam":false,"objectscaleDashboard":true,"objectscaleSystems":false,"replications":false,"uiLoggingLevel":"ERROR"}';
                }
                location / {
                    root   /usr/share/nginx/html;
                    index  index.html index.htm;
                }
            }
        }
      plugin.json: |
        {
            "manifestVersion": "1.0.0",
            "requirements": {
                "plugin.api.version": "1.0.0"
            },
            "configuration": {
                "nameKey": "plugin.name",
                "icon": {
                    "name": "star"
                },
                "sso": {
                    "saml": {
                        "hokSolution": {
                            "pushHook": {
                                "uri": "rest/saml-hook"
                            }
                        }
                    }
                }
            },
            "objects": {
                "ClusterComputeResource": {
                    "summary": {
                        "view": {
                            "uri": "index.html?view=summary",
                            "size": {
                                "widthSpan": 1,
                                "heightSpan": 2
                            }
                        }
                    },
                    "monitor": {
                        "views": [
                            {
                                "navigationId": "deos.monitor.health",
                                "labelKey": "cluster.monitor.list.health",
                                "uri": "index.html?view=health"
                            }
                        ]
                    },
                    "configure": {
                        "views": [
                            {
                                "navigationId": "deos.configure.dashboard",
                                "labelKey": "cluster.configure.list.dashboard",
                                "uri": "index.html?view=dashboard"
                            },
                            {
                                "navigationId": "deos.configure.accounts",
                                "labelKey": "cluster.configure.list.accounts",
                                "uri": "index.html?view=accounts"
                            },
                            {
                                "navigationId": "deos.configure.objectstores",
                                "labelKey": "cluster.configure.list.objectstores",
                                "uri": "index.html?view=objectstores"
                            },
                            {
                                "navigationId": "deos.configure.objectscalesystems",
                                "labelKey": "cluster.configure.list.objectscalesystems",
                                "uri": "index.html?view=objectscalesystems"
                            },

                            {
                                "navigationId": "deos.configure.settings",
                                "labelKey": "cluster.configure.list.settings",
                                "uri": "index.html?view=settings"
                            }
                        ]
                    }
                }
            },
            "definitions": {
                "iconSpriteSheet": {
                    "uri": "assets/images/sprites.png",
                    "definitions": {
                        "star": {
                            "x": 0,
                            "y": 96
                        }
                    }
                },
                "i18n": {
                    "locales": [
                        "en-US",
                        "de-DE",
                        "fr-FR"
                    ],
                    "definitions": {
                        "plugin.name": {
                            "en-US": "ObjectScale",
                            "de-DE": "ObjectScale",
                            "fr-FR": "ObjectScale"
                        },
                        "cluster.monitor.list.health": {
                            "en-US": "Health",
                            "de-DE": "Gesundheit",
                            "fr-FR": "santé"
                        },
                        "cluster.configure.list.objectstores": {
                            "en-US": "Object Stores",
                            "de-DE": "Object Stores",
                            "fr-FR": "Object Stores"
                        },
                        "cluster.configure.list.settings": {
                            "en-US": "Settings",
                            "de-DE": "Settings",
                            "fr-FR": "Settings"
                        },
                        "cluster.configure.list.dashboard": {
                            "en-US": "Dashboard",
                            "de-DE": "Dashboard",
                            "fr-FR": "Dashboard"
                        },
                        "cluster.configure.list.accounts": {
                            "en-US": "Accounts",
                            "de-DE": "Accounts",
                            "fr-FR": "Accounts"
                        },
                        "cluster.configure.list.objectscalesystems": {
                            "en-US": "Objectscale Systems",
                            "de-DE": "Objectscale Systems",
                            "fr-FR": "Objectscale Systems"
                        }
                    }
                }
            }
        }
    ---
    # Source: objectscale-vsphere/charts/objectscale-portal/charts/objectscale-graphql/charts/helm-controller/templates/controller-rbac.yaml
    kind: ClusterRole
    apiVersion: rbac.authorization.k8s.io/v1
    metadata:
      name: {{ .service.namespace }}-install-controller
      labels:
        app.kubernetes.io/name: objectscale-manager
        app.kubernetes.io/instance: vsphere-plugin
        app.kubernetes.io/managed-by: Helm
        app.kubernetes.io/version: 0.70.1
        app.kubernetes.io/component: objectscale-operator
        app.kubernetes.io/part-of: vsphere-plugin
        helm.sh/chart: helm-controller-0.70.1
        release: vsphere-plugin
        operator: objectscale-operator
        product: objectscale
    rules:
      - apiGroups:
          - rbac.authorization.k8s.io
        resources:
          - roles
          - rolebindings
          - clusterroles
          - clusterrolebindings
        verbs:
          - '*'
      - apiGroups:
          - ecs.dellemc.com
        resources:
          - "*"
        verbs:
          - "*"
      - apiGroups:
          - decks.ecs.dellemc.com
        resources:
          - "*"
        verbs:
          - "*"
      - apiGroups:
          - kahm.emcecs.github.com
        resources:
          - "*"
        verbs:
          - "*"
      - apiGroups:
          - storage.k8s.io
        resources:
          - storageclasses
          - storageclasslists
        verbs:
          - get
          - list
      - apiGroups:
          - ""
        resources:
          - pods
          - services
          - endpoints
          - persistentvolumeclaims
          - persistentvolumes
          - events
          - configmaps
          - secrets
          - serviceaccounts
        verbs:
          - "*"
      - apiGroups:
          - batch
        resources:
          - jobs
          - cronjobs
        verbs:
          - "*"
      - apiGroups:
          - certificates.k8s.io
        resources:
          - certificatesigningrequests
        verbs:
          - "*"
      - apiGroups:
          - certificates.k8s.io
        resources:
          - certificatesigningrequests/approval
        verbs:
          - update
      - apiGroups:
          - policy
        resources:
          - poddisruptionbudgets
        verbs:
          - "*"
      - apiGroups:
          - apps
        resources:
          - deployments
          - daemonsets
          - replicasets
          - statefulsets
        verbs:
          - "*"
      - apiGroups:
          - zookeeper.pravega.io
        resources:
          - "*"
        verbs:
          - "*"
      - apiGroups:
          - app.k8s.io
        resources:
          - "*"
        verbs:
          - "*"
      - apiGroups:
          - atlas.dellemc.com
        resources:
          - "*"
        verbs:
          - "*"
      - apiGroups:
          - influxdata.com
        resources:
          - influxdbs
        verbs:
          - "*"
      - apiGroups:
          - ""
        resources:
          - nodes
          - clusterroles
        verbs:
          - "*"
      - apiGroups:
        - apiextensions.k8s.io
        resources:
        - customresourcedefinitions
        verbs:
        - '*'
      - apiGroups:
        - ""
        resources:
        - namespaces
        verbs:
        - list
        - get
      - apiGroups:
          - stateful.ecs.dellemc.com
        resources:
          - "*"
        verbs:
          - "*"
      - apiGroups:
        - "admissionregistration.k8s.io"
        resources:
        - "mutatingwebhookconfigurations"
        - "validatingwebhookconfigurations"
        verbs:
          - "*"
      - apiGroups:
          - db.ecs.dellemc.com
        resources:
          - "*"
        verbs:
          - "*"
    ---
    # Source: objectscale-vsphere/charts/objectscale-portal/charts/objectscale-graphql/templates/object-store-admin-role.yaml
    kind: ClusterRole
    apiVersion: rbac.authorization.k8s.io/v1
    metadata:
      name: {{ .service.namespace }}-object-store-admin
      labels:
        app.kubernetes.io/name: objectscale-manager
        app.kubernetes.io/instance: vsphere-plugin
        app.kubernetes.io/managed-by: Helm
        app.kubernetes.io/version: 0.70.1
        app.kubernetes.io/component: objectscale-graphql
        app.kubernetes.io/part-of: vsphere-plugin
        helm.sh/chart: objectscale-graphql-0.70.1
        release: vsphere-plugin
        operator: objectscale-operator
        product: objectscale
        rbac.authorization.k8s.io/aggregate-to-edit: "true"
    rules:
    - apiGroups:
      - ecs.dellemc.com
      resources:
      - ecsclusters
      verbs:
      - "*"
    - apiGroups:
      - app.k8s.io
      resources:
      - "*"
      verbs:
      - "*"
    - apiGroups:
      - influxdata.com
      resources:
      - influxdbs
      verbs:
      - "*"
    - apiGroups:
        - ""
      resources:
        - pods
        - persistentvolumeclaims
        - secrets
        - configmaps
      verbs:
        - "*"
    - apiGroups:
        - batch
      resources:
        - jobs
        - cronjobs
      verbs:
        - "*"
    - apiGroups:
        - appplatform.wcp.vmware.com
      resources:
        - storagepolicies
      verbs:
        - get
        - list
    ---
    # Source: objectscale-vsphere/charts/objectscale-portal/charts/objectscale-graphql/templates/object-store-monitor-role.yaml
    kind: ClusterRole
    apiVersion: rbac.authorization.k8s.io/v1
    metadata:
      name: {{ .service.namespace }}-object-store-monitor
      labels:
        app.kubernetes.io/name: objectscale-manager
        app.kubernetes.io/instance: vsphere-plugin
        app.kubernetes.io/managed-by: Helm
        app.kubernetes.io/version: 0.70.1
        app.kubernetes.io/component: objectscale-graphql
        app.kubernetes.io/part-of: vsphere-plugin
        helm.sh/chart: objectscale-graphql-0.70.1
        release: vsphere-plugin
        operator: objectscale-operator
        product: objectscale
        rbac.authorization.k8s.io/aggregate-to-edit: "true"
        rbac.authorization.k8s.io/aggregate-to-view: "true"
    rules:
    - apiGroups:
      - ecs.dellemc.com
      resources:
      - ecsclusters
      verbs:
      - get
      - list
      - watch
    - apiGroups:
        - ecs.dellemc.com
      resources:
        - networkconnections
      verbs:
        - get
        - watch
        - list
    - apiGroups:
      - ""
      resources:
      - pods
      - services
      - endpoints
      - persistentvolumeclaims
      - persistentvolumes
      - events
      - configmaps
      - secrets
      - resourcequotas
      verbs:
      - get
      - watch
      - list
    - apiGroups:
      - batch
      resources:
      - jobs
      - cronjobs
      verbs:
      - get
      - watch
      - list
    - apiGroups:
      - policy
      resources:
      - poddisruptionbudgets
      verbs:
      - get
      - watch
      - list
    - apiGroups:
      - apps
      resources:
      - deployments
      - daemonsets
      - replicasets
      - statefulsets
      verbs:
      - get
      - watch
      - list
    - apiGroups:
      - zookeeper.pravega.io
      resources:
      - "*"
      verbs:
      - get
      - watch
      - list
    - apiGroups:
      - app.k8s.io
      resources:
      - "*"
      verbs:
      - get
      - list
      - watch
    - apiGroups:
      - atlas.dellemc.com
      resources:
      - "*"
      verbs:
      - get
      - watch
      - list
    - apiGroups:
      - influxdata.com
      resources:
      - influxdbs
      verbs:
      - "*"
    - apiGroups:
        - metrics.k8s.io
      resources:
        - "*"
      verbs:
        - get
        - watch
        - list
    - apiGroups:
        - appplatform.wcp.vmware.com
      resources:
        - storagepolicies
      verbs:
        - get
        - list
    - apiGroups:
        - appplatform.wcp.vmware.com
      resources:
        - storagepolicies
      verbs:
        - get
        - list
    ---
    # Source: objectscale-vsphere/charts/objectscale-portal/charts/objectscale-graphql/templates/objectscale-admin-cluster-role.yaml
    kind: ClusterRole
    apiVersion: rbac.authorization.k8s.io/v1
    metadata:
      name: {{ .service.namespace }}-objectscale-admin
      labels:
        app.kubernetes.io/name: objectscale-manager
        app.kubernetes.io/instance: vsphere-plugin
        app.kubernetes.io/managed-by: Helm
        app.kubernetes.io/version: 0.70.1
        app.kubernetes.io/component: graphql-cluster-scoped-resources
        app.kubernetes.io/part-of: vsphere-plugin
        helm.sh/chart: objectscale-graphql-0.70.1
        release: vsphere-plugin
        operator: objectscale-operator
        product: objectscale
    rules:
      - apiGroups:
          - cns.vmware.com
        resources:
          - storagepools
        verbs:
          - get
          - list
      - apiGroups:
          - storage.k8s.io
        resources:
          - storageclasses
          - storageclasslists
        verbs:
          - get
          - list
      - apiGroups:
          - certificates.k8s.io
        resources:
          - certificatesigningrequests
        verbs:
          - "*"
      - apiGroups:
          - certificates.k8s.io
        resources:
          - certificatesigningrequests/approval
        verbs:
          - update
      - apiGroups:
          - certificates.k8s.io
        resourceNames:
          - kubernetes.io/*
        resources:
          - signers
        verbs:
          - approve
      - apiGroups:
          - rbac.authorization.k8s.io
        resources:
          - clusterroles
          - clusterrolebindings
        verbs:
          - "*"
      - apiGroups:
          - ""
        resources:
          - nodes
          - clusterroles
        verbs:
          - "*"
      - apiGroups:
          - ""
        resources:
          - namespaces
          - serviceaccounts
          - secrets
          - resourcequotas
        verbs:
          - get
          - list
          - watch
    ---
    # Source: objectscale-vsphere/charts/objectscale-portal/charts/objectscale-graphql/charts/helm-controller/templates/controller-rbac.yaml
    kind: ClusterRoleBinding
    apiVersion: rbac.authorization.k8s.io/v1
    metadata:
      name: {{ .service.namespace }}-install-controller
      labels:
        app.kubernetes.io/name: objectscale-manager
        app.kubernetes.io/instance: vsphere-plugin
        app.kubernetes.io/managed-by: Helm
        app.kubernetes.io/version: 0.70.1
        app.kubernetes.io/component: helm-controller
        app.kubernetes.io/part-of: vsphere-plugin
        helm.sh/chart: helm-controller-0.70.1
        release: vsphere-plugin
        operator: objectscale-operator
        product: objectscale
    subjects:
      - kind: ServiceAccount
        name: install-controller
        namespace: {{ .service.namespace }}
    roleRef:
      kind: ClusterRole
      name: {{ .service.namespace }}-install-controller
      apiGroup: rbac.authorization.k8s.io
    ---
    # Source: objectscale-vsphere/charts/objectscale-portal/templates/objectscale-api-role-bindings.yaml
    kind: ClusterRoleBinding
    apiVersion: rbac.authorization.k8s.io/v1
    metadata:
      name: {{ .service.namespace }}-objectscale-api-as-admin
      labels:
        app.kubernetes.io/name: objectscale-manager
        app.kubernetes.io/instance: vsphere-plugin
        app.kubernetes.io/managed-by: Helm
        app.kubernetes.io/version: 0.70.2
        app.kubernetes.io/component: objectscale-graphql
        app.kubernetes.io/part-of: vsphere-plugin
        helm.sh/chart: objectscale-portal-0.70.2
        release: vsphere-plugin
        operator: objectscale-operator
        product: objectscale
    subjects:
      - kind: ServiceAccount
        name: objectscale-api
        namespace: {{ .service.namespace }}
    roleRef:
      kind: ClusterRole
      name: {{ .service.namespace }}-objectscale-admin
      apiGroup: rbac.authorization.k8s.io
    ---
    # Source: objectscale-vsphere/charts/objectscale-portal/charts/objectscale-graphql/templates/objecscale-api-rbac.yaml
    kind: Role
    apiVersion: rbac.authorization.k8s.io/v1
    metadata:
      name: {{ .service.namespace }}-objectscale-api
      namespace: {{ .service.namespace }}
      labels:
        app.kubernetes.io/name: objectscale-manager
        app.kubernetes.io/instance: vsphere-plugin
        app.kubernetes.io/managed-by: Helm
        app.kubernetes.io/version: 0.70.1
        app.kubernetes.io/component: objectscale-graphql
        app.kubernetes.io/part-of: vsphere-plugin
        helm.sh/chart: objectscale-graphql-0.70.1
        release: vsphere-plugin
        operator: objectscale-operator
        product: objectscale
    rules:
    - apiGroups:
      - ""
      resources:
      - secrets
      verbs:
        - "*"
    ---
    # Source: objectscale-vsphere/charts/objectscale-portal/charts/objectscale-graphql/templates/objectscale-admin-role.yaml
    kind: Role
    apiVersion: rbac.authorization.k8s.io/v1
    metadata:
      name: {{ .service.namespace }}-objectscale-admin
      namespace: {{ .service.namespace }}
      labels:
        app.kubernetes.io/name: objectscale-manager
        app.kubernetes.io/instance: vsphere-plugin
        app.kubernetes.io/managed-by: Helm
        app.kubernetes.io/version: 0.70.1
        app.kubernetes.io/component: objectscale-graphql
        app.kubernetes.io/part-of: vsphere-plugin
        helm.sh/chart: objectscale-graphql-0.70.1
        release: vsphere-plugin
        operator: objectscale-operator
        product: objectscale
    rules:
    - apiGroups:
        - decks.ecs.dellemc.com
      resources:
        - "*"
      verbs:
        - "*"
    - apiGroups:
        - ecs.dellemc.com
      resources:
        - "*"
      verbs:
        - "*"
    - apiGroups:
        - kahm.emcecs.github.com
      resources:
        - "*"
      verbs:
        - "*"
    - apiGroups:
        - ""
      resources:
        - secrets
        - pods
        - services
        - endpoints
        - persistentvolumeclaims
        - persistentvolumes
        - events
        - configmaps
      verbs:
        - "*"
    - apiGroups:
        - batch
      resources:
        - jobs
        - cronjobs
      verbs:
        - "*"
    - apiGroups:
        - policy
      resources:
        - poddisruptionbudgets
      verbs:
        - get
        - list
        - watch
    - apiGroups:
        - apps
      resources:
        - deployments
        - daemonsets
        - replicasets
        - statefulsets
      verbs:
        - "*"
    - apiGroups:
        - app.k8s.io
      resources:
        - "*"
      verbs:
        - "*"
    - apiGroups:
        - metrics.k8s.io
      resources:
        - "*"
      verbs:
        - get
        - watch
        - list
    - apiGroups:
        - appplatform.wcp.vmware.com
      resources:
        - storagepolicies
      verbs:
        - get
        - list
    ---
    # Source: objectscale-vsphere/charts/objectscale-portal/charts/rsyslog-client/templates/rbac_role.yaml
    #
    # Copyright © [2020] Dell Inc. or its subsidiaries.
    # All Rights Reserved.
    #
    # This software contains the intellectual property of Dell Inc.
    # or is licensed to Dell Inc. from third parties. Use of this
    # software and the intellectual property contained therein is expressly
    # limited to the terms and conditions of the License Agreement under which
    # it is provided by or on behalf of Dell Inc. or its subsidiaries.
    #
    #
    #  Role for rsyslog-client to find instance of rsyslog service
    apiVersion: rbac.authorization.k8s.io/v1
    kind: Role
    metadata:
      labels:
        app.kubernetes.io/name: vsphere-plugin-rsyslog-client
        app.kubernetes.io/instance: vsphere-plugin
        app.kubernetes.io/managed-by: Helm
        app.kubernetes.io/version: "0.54.0"
        app.kubernetes.io/part-of: vsphere-plugin
        helm.sh/chart: rsyslog-client-3.7.0-1164.08aefd2c
        release: vsphere-plugin
      name: "vsphere-plugin-rsyslog-client"
      namespace: "{{ .service.namespace }}"
    rules:
      - apiGroups: [""]
        resources: ["pods"]
        verbs: ["list"]
    ---
    # Source: objectscale-vsphere/templates/vsphere-plugin-network-policy.yaml
    apiVersion: rbac.authorization.k8s.io/v1
    kind: Role
    metadata:
      name: objectscale-default-role
      namespace: {{ .service.namespace }}
    rules:
      - apiGroups:
          - policy
        resourceNames:
          - wcp-privileged-psp
        resources:
          - podsecuritypolicies
        verbs:
          - use
    ---
    # Source: objectscale-vsphere/charts/objectscale-portal/charts/objectscale-graphql/templates/objecscale-api-rbac.yaml
    kind: RoleBinding
    apiVersion: rbac.authorization.k8s.io/v1
    metadata:
      name: {{ .service.namespace }}-objectscale-api
      namespace: {{ .service.namespace }}
      labels:
        app.kubernetes.io/name: objectscale-manager
        app.kubernetes.io/instance: vsphere-plugin
        app.kubernetes.io/managed-by: Helm
        app.kubernetes.io/version: 0.70.1
        app.kubernetes.io/component: objectscale-graphql
        app.kubernetes.io/part-of: vsphere-plugin
        helm.sh/chart: objectscale-graphql-0.70.1
        release: vsphere-plugin
        operator: objectscale-operator
        product: objectscale
    subjects:
    - kind: ServiceAccount
      name: objectscale-api
      namespace: {{ .service.namespace }}
    roleRef:
      kind: Role
      name: {{ .service.namespace }}-objectscale-api
      apiGroup: rbac.authorization.k8s.io
    ---
    # Source: objectscale-vsphere/charts/objectscale-portal/charts/rsyslog-client/templates/rbac_rolebinding.yaml
    #
    # Copyright © [2020] Dell Inc. or its subsidiaries.
    # All Rights Reserved.
    #
    # This software contains the intellectual property of Dell Inc.
    # or is licensed to Dell Inc. from third parties. Use of this
    # software and the intellectual property contained therein is expressly
    # limited to the terms and conditions of the License Agreement under which
    # it is provided by or on behalf of Dell Inc. or its subsidiaries.
    #
    #
    #  RoleBinding for rsyslog-client to find instance of rsyslog service
    kind: RoleBinding
    apiVersion: rbac.authorization.k8s.io/v1beta1
    metadata:
      name: "vsphere-plugin-rsyslog-client"
      namespace: "{{ .service.namespace }}"
      labels:
        app.kubernetes.io/name: vsphere-plugin-rsyslog-client
        app.kubernetes.io/instance: vsphere-plugin
        app.kubernetes.io/managed-by: Helm
        app.kubernetes.io/version: "0.54.0"
        app.kubernetes.io/part-of: vsphere-plugin
        helm.sh/chart: rsyslog-client-3.7.0-1164.08aefd2c
        release: vsphere-plugin
    subjects:
      - apiGroup: rbac.authorization.k8s.io
        kind: Group
        name: system:serviceaccounts
    roleRef:
      kind: Role
      apiGroup: rbac.authorization.k8s.io
      name: "vsphere-plugin-rsyslog-client"
    ---
    # Source: objectscale-vsphere/charts/objectscale-portal/templates/objectscale-api-role-bindings.yaml
    kind: RoleBinding
    apiVersion: rbac.authorization.k8s.io/v1
    metadata:
      name: {{ .service.namespace }}-objectscale-api-as-admin
      namespace: {{ .service.namespace }}
      labels:
        app.kubernetes.io/name: objectscale-manager
        app.kubernetes.io/instance: vsphere-plugin
        app.kubernetes.io/managed-by: Helm
        app.kubernetes.io/version: 0.70.2
        app.kubernetes.io/component: objectscale-graphql
        app.kubernetes.io/part-of: vsphere-plugin
        helm.sh/chart: objectscale-portal-0.70.2
        release: vsphere-plugin
        operator: objectscale-operator
        product: objectscale
    subjects:
      - kind: ServiceAccount
        name: objectscale-api
        namespace: {{ .service.namespace }}
    roleRef:
      kind: Role
      name: {{ .service.namespace }}-objectscale-admin
      apiGroup: rbac.authorization.k8s.io
    ---
    # Source: objectscale-vsphere/templates/vsphere-plugin-network-policy.yaml
    apiVersion: rbac.authorization.k8s.io/v1
    kind: RoleBinding
    metadata:
      name: objectscale-default-binding
      namespace: {{ .service.namespace }}
    roleRef:
      apiGroup: rbac.authorization.k8s.io
      kind: Role
      name: objectscale-default-role
    subjects:
      - kind: ServiceAccount
        name: default
        namespace: {{ .service.namespace }}
    ---
    # Source: objectscale-vsphere/charts/objectscale-portal/charts/objectscale-graphql/charts/helm-controller/templates/service.yaml
    apiVersion: v1
    kind: Service
    metadata:
      name: vsphere-plugin-installer
      namespace: {{ .service.namespace }}
      labels:
        app.kubernetes.io/name: objectscale-manager
        app.kubernetes.io/component: objectscale-install-controller
        helm.sh/chart: helm-controller-0.70.1
        app.kubernetes.io/instance: vsphere-plugin
        app.kubernetes.io/version: 0.70.1
        app.kubernetes.io/part-of: vsphere-plugin
        release: vsphere-plugin
        operator: objectscale-operator
        product: objectscale
        io.kompose.service: helm-controller
    spec:
      type: ClusterIP
      ports:
        - name: http
          port: 80
          targetPort: 8080
      selector:
        app.kubernetes.io/name: objectscale-manager
        app.kubernetes.io/component: objectscale-install-controller
    ---
    # Source: objectscale-vsphere/charts/objectscale-portal/charts/objectscale-graphql/templates/graphql-service.yaml
    apiVersion: v1
    kind: Service
    metadata:
      name: objectscale-graphql
      namespace: {{ .service.namespace }}
      labels:
        app.kubernetes.io/name: objectscale-manager
        app.kubernetes.io/instance: vsphere-plugin
        app.kubernetes.io/managed-by: Helm
        app.kubernetes.io/version: 0.70.1
        app.kubernetes.io/component: objectscale-graphql
        app.kubernetes.io/part-of: vsphere-plugin
        helm.sh/chart: objectscale-graphql-0.70.1
        release: vsphere-plugin
        operator: objectscale-operator
        product: objectscale
    spec:
      type: ClusterIP
      selector:
        app.kubernetes.io/name: objectscale-manager
        app.kubernetes.io/component: objectscale-graphql
      ports:
        - port: 8080
          name: http
    ---
    # Source: objectscale-vsphere/charts/objectscale-portal/templates/objectscale-portal-service.yaml
    apiVersion: v1
    kind: Service
    metadata:
      name: objectscale-portal
      namespace: {{ .service.namespace }}
      labels:
        app.kubernetes.io/name: objectscale-manager
        app.kubernetes.io/instance: vsphere-plugin
        app.kubernetes.io/managed-by: Helm
        app.kubernetes.io/version: 0.70.2
        app.kubernetes.io/component: objectscale-portal
        app.kubernetes.io/part-of: vsphere-plugin
        helm.sh/chart: objectscale-portal-0.70.2
        release: vsphere-plugin
        operator: objectscale-operator
        product: objectscale
    spec:
      type: ClusterIP
      selector:
        app.kubernetes.io/name: objectscale-manager
        app.kubernetes.io/component: objectscale-portal
      ports:
          - name: https
            port: 4443
            targetPort: 4443
    ---
    # Source: objectscale-vsphere/charts/objectscale-portal/charts/objectscale-graphql/charts/helm-controller/templates/deployment.yaml
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: objectscale-install-controller
      namespace: {{ .service.namespace }}
      labels:
        app.kubernetes.io/name: objectscale-manager
        app.kubernetes.io/component: objectscale-install-controller
        app.kubernetes.io/managed-by: Helm
        app.kubernetes.io/instance: vsphere-plugin
        app.kubernetes.io/version: 0.70.1
        app.kubernetes.io/part-of: vsphere-plugin
        helm.sh/chart: helm-controller-0.70.1
        release: vsphere-plugin
        operator: objectscale-operator
        product: objectscale
    spec:
      replicas: 1
      selector:
        matchLabels:
          app.kubernetes.io/name: objectscale-manager
          app.kubernetes.io/component: objectscale-install-controller
      template:
        metadata:
          labels:
            app.kubernetes.io/name: objectscale-manager
            app.kubernetes.io/component: objectscale-install-controller
            app.kubernetes.io/managed-by: Helm
            app.kubernetes.io/instance: vsphere-plugin
            app.kubernetes.io/version: 0.70.1
            app.kubernetes.io/part-of: vsphere-plugin
            helm.sh/chart: helm-controller-0.70.1
            release: vsphere-plugin
            operator: objectscale-operator
            product: objectscale
        spec:
          serviceAccountName: install-controller
          imagePullSecrets:
            - name: vsphere-docker-secret
          containers:
            - name: objectscale-install-controller
              resources:
                limits:
                  memory: 500M
                requests:
                  memory: 250M
              image: {{ .Values.registryName }}/install-controller:0.70.0
              env:
                - name: OPERATOR_NAME
                  value: objectscale-operator
                - name: MY_POD_IP
                  valueFrom:
                    fieldRef:
                      fieldPath: status.podIP
                - name: REST_PORT
                  value: "8080"
                - name: REST_CREDENTIALS
                  valueFrom:
                    secretKeyRef:
                      name: vsphere-plugin-rest-credentials
                      key: credentials
                - name: WATCH_NAMESPACE
                  valueFrom:
                    fieldRef:
                      fieldPath: metadata.namespace
              imagePullPolicy: IfNotPresent
              ports:
                - containerPort: 8080
                  name: http
    ---
    # Source: objectscale-vsphere/charts/objectscale-portal/charts/objectscale-graphql/templates/graphql-deployment.yaml
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: objectscale-graphql
      namespace: {{ .service.namespace }}
      labels:
        app.kubernetes.io/name: objectscale-manager
        app.kubernetes.io/instance: vsphere-plugin
        app.kubernetes.io/managed-by: Helm
        app.kubernetes.io/version: 0.70.1
        app.kubernetes.io/component: objectscale-graphql
        app.kubernetes.io/part-of: vsphere-plugin
        helm.sh/chart: objectscale-graphql-0.70.1
        release: vsphere-plugin
        operator: objectscale-operator
        product: objectscale
    spec:
      replicas: 1
      selector:
        matchLabels:
          app.kubernetes.io/name: objectscale-manager
          app.kubernetes.io/component: objectscale-graphql
      template:
        metadata:
          labels:
            app.kubernetes.io/name: objectscale-manager
            app.kubernetes.io/component: objectscale-graphql
            app.kubernetes.io/managed-by: Helm
            app.kubernetes.io/instance: vsphere-plugin
            app.kubernetes.io/part-of: vsphere-plugin
            app.kubernetes.io/version: 0.70.1
            helm.sh/chart: objectscale-graphql-0.70.1
            release: vsphere-plugin
            operator: objectscale-operator
            product: objectscale
        spec:
          serviceAccountName: objectscale-api
          containers:
          - name: objectscale-graphql
            image: {{ .Values.registryName }}/ecs-flex-graphql:0.70.0
            imagePullPolicy: IfNotPresent
            env:
            - name: OBJSTORE_AVAILABLE_VERSIONS
              value: "[\"0.70.0\"]"
            - name: GRAPHQL_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: WATCH_NAMESPACE
              valueFrom:
                fieldRef:
                  fieldPath: metadata.namespace
            - name: GLOBAL_REGISTRY
              value: {{ .Values.registryName }}
            - name: GLOBAL_REGISTRY_SECRET
              value: vsphere-docker-secret
            - name: LICENSE_CHART_VERSION
              value: 2.70.0
            - name: SUPPORTASSIST_CHART_VERSION
              value: 2.70.0
            - name: SRSGATEWAY_CHART_VERSION
              value: 1.2.0
            - name: OPERATOR_NAME
              value: objectscale-operator
            - name: MANAGER_RELEASE_NAME
              value: objectscale-manager
            - name: VSPHERE_SERVICE_PREFIX
              value: {{ .service.prefix }}
            - name: STORAGE_CLASS_NAME
              value: dellemc-objectscale-highly-available
            - name: LOG_DIRECTION
              value: stdout
            - name: HELM_CONTROLLER_ENDPOINT
              value: http://vsphere-plugin-installer
            - name: HELM_CONTROLLER_REST_CREDENTIALS
              valueFrom:
                secretKeyRef:
                  name: vsphere-plugin-rest-credentials
                  key: credentials

          - name: rsyslog
            image: "{{ .Values.registryName }}/rsyslog:3.7.0.0-1161.35f87a27"
            imagePullPolicy: "IfNotPresent"
            env:
              - name: POD_NAME
                valueFrom:
                  fieldRef:
                    fieldPath: metadata.name
              - name: POD_UID
                valueFrom:
                  fieldRef:
                    fieldPath: metadata.uid
              - name: POD_NAMESPACE
                value: "{{ .service.namespace }}"
              - name: LOG_STDOUT_ENABLED
                value: ""
              - name: NODE_NAME
                valueFrom:
                  fieldRef:
                    fieldPath: spec.nodeName
              - name: RSYSLOG_CLIENT
                value: "true"
              - name: RSYSLOG_SVC_NAME
                value: objectscale-manager-rsyslog
              - name: RSYSLOG_SVC_NAMESPACE
                value: {{ .service.namespace }}
            volumeMounts:
              - mountPath: /etc/rsyslog
                name: rsyslog-config
          volumes:

          - name: rsyslog-config
            configMap:
              name: vsphere-plugin-rsyslog-client-config
    ---
    # Source: objectscale-vsphere/charts/objectscale-portal/templates/objectscale-portal-deployment.yaml
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: objectscale-portal
      namespace: {{ .service.namespace }}
      labels:
        app.kubernetes.io/name: objectscale-manager
        app.kubernetes.io/instance: vsphere-plugin
        app.kubernetes.io/managed-by: Helm
        app.kubernetes.io/version: 0.70.2
        app.kubernetes.io/component: objectscale-portal
        app.kubernetes.io/part-of: vsphere-plugin
        helm.sh/chart: objectscale-portal-0.70.2
        release: vsphere-plugin
        operator: objectscale-operator
        product: objectscale
    spec:
      replicas: 1
      selector:
        matchLabels:
          app.kubernetes.io/name: objectscale-manager
          app.kubernetes.io/component: objectscale-portal
      template:
        metadata:
          labels:
            app.kubernetes.io/name: objectscale-manager
            app.kubernetes.io/component: objectscale-portal
            app.kubernetes.io/managed-by: Helm
            app.kubernetes.io/instance: vsphere-plugin
            app.kubernetes.io/part-of: vsphere-plugin
            app.kubernetes.io/version: 0.70.2
            helm.sh/chart: objectscale-portal-0.70.2
            release: vsphere-plugin
            operator: objectscale-operator
            product: objectscale
        spec:
          imagePullSecrets:
            - name: vsphere-docker-secret
          volumes:
            - name: config-volume
              configMap:
                name: objectscale-portal
            - name: certificate
              secret:
                secretName: objectscale-plugin-secret
          containers:
            - name: objectscale-portal
              image: {{ .Values.registryName }}/ecs-flex-vsphere-plugin:0.70.2
              env:
                - name: OPERATOR_NAME
                  value: objectscale-operator
              imagePullPolicy: IfNotPresent
              volumeMounts:
                - name: config-volume
                  mountPath: /usr/share/nginx/html/plugin.json
                  subPath: plugin.json
                - name: config-volume
                  mountPath: /conf/upstream.conf
                  subPath: upstream.conf
                - name: config-volume
                  mountPath: /etc/nginx/nginx.conf
                  subPath: nginx.conf
                - name: certificate
                  mountPath: /etc/nginx/ssl
    ---
    # Source: objectscale-vsphere/templates/persistent-services-platform-sp-ha.yaml
    apiVersion: appplatform.wcp.vmware.com/v1beta1
    kind: StoragePolicy
    metadata:
      labels:
        controller-tools.k8s.io: "1.0"
      name: dellemc-objectscale-highly-available
      namespace: {{ .service.namespace }}
    spec:
      name: dellemc-objectscale-highly-available
      rules:
        VSAN.hostFailuresToTolerate: "1"
        VSAN.stripeWidth: "1"
    ---
    # Source: objectscale-vsphere/templates/persistent-services-platform-operator.yaml
    apiVersion: appplatform.wcp.vmware.com/v1beta1
    kind: VCUIPlugin
    metadata:
      labels:
        controller-tools.k8s.io: "1.0"
      name: objectscale-ui-{{ .service.namespace }}
      namespace: {{ .service.namespace }}
    spec:
      name: objectscale-{{ .service.namespace }}
      uiBackendSecret: objectscale-plugin-secret
      uiBackendService: objectscale-portal
      vSphereUiPluginUrl: /plugin.json
      vSphereExtensionKey: com.dellemc.vsphere.plugin.{{ .service.namespace }}
    ---
    # Source: objectscale-vsphere/charts/objectscale-portal/charts/objectscale-graphql/charts/helm-controller/templates/rest-credentials-secret.yaml
    apiVersion: v1
    kind: Secret
    metadata:
      name: vsphere-plugin-rest-credentials
      namespace: {{ .service.namespace }}
      annotations:
        "helm.sh/hook": "pre-install"
        "helm.sh/hook-delete-policy": "before-hook-creation"
    type: Opaque
    stringData:
      credentials: objectscale:guuTkL2mKhm3vMll:j5DtdcYAzQt9rYq4
    ---
    ---
    # Source: objectscale-manager/templates/objectscale-manager-app.yaml
    apiVersion: app.k8s.io/v1beta1
    kind: Application
    metadata:
      name: objectscale-manager
      namespace: {{ .service.namespace }}
      labels:
        app.kubernetes.io/name: objectscale-manager
        app.kubernetes.io/version: 0.70.2
        app.kubernetes.io/instance: objectscale-manager
        app.kubernetes.io/managed-by: nautilus
        helm.sh/chart: objectscale-manager-0.70.2
        release: objectscale-manager
        product: objectscale
      annotations:
        com.dellemc.kahm.subscribed: "true"
        nautilus.dellemc.com/run-level: "10"
        nautilus.dellemc.com/chart-name: objectscale-manager
        nautilus.dellemc.com/chart-version: 0.70.2
        nautilus.dellemc.com/chart-values: "{\"affinity\":{},\"atlas\":{\"enabled\":true},\"atlas-operator\":{\"affinity\":{},\"global\":{\"enableHealthcheck\":false,\"labels\":{},\"logging_injection_enabled\":true,\"monitoring\":{\"enabled\":true},\"monitoring_registry\":\"{{ .Values.registryName }}\",\"platform\":\"VMware\",\"product\":\"objectscale\",\"registry\":\"{{ .Values.registryName }}\",\"registrySecret\":\"vsphere-docker-secret\",\"rsyslog_enabled\":true,\"storageClassName\":\"dellemc-objectscale-highly-available\",\"watchAllNamespaces\":false},\"image\":{\"pullPolicy\":\"IfNotPresent\",\"repository\":\"atlas-operator\"},\"nameOverride\":\"\",\"nodeSelector\":{},\"podSecurityContext\":{},\"resources\":{\"limits\":{\"cpu\":1,\"memory\":\"500Mi\"},\"requests\":{\"cpu\":\"250m\",\"memory\":\"300Mi\"}},\"securityContext\":{},\"tolerations\":[]},\"bookkeeper\":{\"enabled\":true},\"bookkeeper-operator\":{\"crd\":{\"create\":true},\"global\":{\"enableHealthcheck\":false,\"logging_injection_enabled\":true,\"monitoring\":{\"enabled\":true},\"monitoring_registry\":\"{{ .Values.registryName }}\",\"platform\":\"VMware\",\"product\":\"objectscale\",\"registry\":\"{{ .Values.registryName }}\",\"registrySecret\":\"vsphere-docker-secret\",\"rsyslog_enabled\":true,\"storageClassName\":\"dellemc-objectscale-highly-available\",\"watchAllNamespaces\":false},\"hooks\":{\"backoffLimit\":10,\"image\":{\"repository\":\"k8s-kubectl\",\"tag\":\"v1.16.10\"}},\"image\":{\"pullPolicy\":\"IfNotPresent\",\"repository\":\"bookkeeper-operator\",\"tag\":\"0.1.3-50-f528f6f\"},\"rbac\":{\"create\":true},\"serviceAccount\":{\"create\":true,\"name\":\"bookkeeper-operator\"},\"testmode\":{\"enabled\":true,\"version\":\"0.9.0\"},\"watchNamespace\":\"\",\"webhookCert\":{\"certName\":\"selfsigned-cert-bk\",\"generate\":false,\"secretName\":\"selfsigned-cert-tls-bk\"}},\"createApplicationResource\":false,\"dcm\":{\"atlas\":{\"affinity\":false,\"image\":{\"pullPolicy\":\"IfNotPresent\",\"repository\":\"atlas\",\"tag\":\"1.1.3\"},\"persistence\":{\"size\":\"1Gi\"}},\"common-monitoring-lib\":{\"exports\":{\"default\":{\"rsyslog_client_image_pull_policy\":\"IfNotPresent\",\"rsyslog_client_tag\":\"3.7.0.0-1146.a692701d\"}},\"global\":{\"enableHealthcheck\":false,\"logging_injection_enabled\":true,\"monitoring\":{\"enabled\":true},\"monitoring_registry\":\"{{ .Values.registryName }}\",\"performanceProfile\":\"Small\",\"platform\":\"VMware\",\"product\":\"objectscale\",\"registry\":\"{{ .Values.registryName }}\",\"registrySecret\":\"vsphere-docker-secret\",\"rsyslog_enabled\":true,\"storageClassName\":\"dellemc-objectscale-highly-available\",\"watchAllNamespaces\":false}},\"enabled\":true,\"global\":{\"enableHealthcheck\":false,\"logging_injection_enabled\":true,\"monitoring\":{\"enabled\":true},\"monitoring_registry\":\"{{ .Values.registryName }}\",\"performanceProfile\":\"Small\",\"platform\":\"VMware\",\"product\":\"objectscale\",\"registry\":\"{{ .Values.registryName }}\",\"registrySecret\":\"vsphere-docker-secret\",\"rsyslog_enabled\":true,\"storageClassName\":\"dellemc-objectscale-highly-available\",\"watchAllNamespaces\":false},\"image\":{\"pullPolicy\":\"IfNotPresent\",\"repository\":\"dcm\"},\"livenessProbe\":{\"probePath\":\"/dcmhealthcheck\"},\"readinessProbe\":{\"probePath\":\"/dcmhealthcheck\"},\"replicaCount\":1,\"service\":{\"port\":9026,\"targetPort\":9026,\"type\":\"LoadBalancer\"},\"tag\":\"0.70.2\"},\"debugMode\":false,\"ecs-monitoring\":{\"influxdb\":{\"persistence\":{\"storageClassName\":\"dellemc-objectscale-highly-available\"}}},\"federation\":{\"enabled\":true,\"fedsvc\":{\"image\":{\"pullPolicy\":\"IfNotPresent\",\"repository\":\"fedsvc\"},\"livenessProbe\":{\"probePath\":\"/fedsvchealthcheck\"},\"readinessProbe\":{\"probePath\":\"/fedsvchealthcheck\"},\"replicaCount\":3,\"service\":{\"port\":9500,\"type\":\"LoadBalancer\"}},\"global\":{\"enableHealthcheck\":false,\"logging_injection_enabled\":true,\"monitoring\":{\"enabled\":true},\"monitoring_registry\":\"{{ .Values.registryName }}\",\"platform\":\"VMware\",\"product\":\"objectscale\",\"registry\":\"{{ .Values.registryName }}\",\"registrySecret\":\"vsphere-docker-secret\",\"rsyslog_enabled\":true,\"storageClassName\":\"dellemc-objectscale-highly-available\",\"watchAllNamespaces\":false},\"tag\":\"0.70.2\"},\"fluentbitAgent\":{\"image\":{\"repository\":\"fluent-bit\",\"tag\":\"0.28.0\"}},\"global\":{\"enableHealthcheck\":false,\"logging_injection_enabled\":true,\"monitoring\":{\"enabled\":true},\"monitoring_registry\":\"{{ .Values.registryName }}\",\"platform\":\"VMware\",\"product\":\"objectscale\",\"registry\":\"{{ .Values.registryName }}\",\"registrySecret\":\"vsphere-docker-secret\",\"rsyslog_enabled\":true,\"storageClassName\":\"dellemc-objectscale-highly-available\",\"watchAllNamespaces\":false},\"healthChecks\":{\"preUpdate\":{\"image\":{\"repository\":\"objectscale-manager-pre-update\"}}},\"hooks\":{\"registry\":\"{{ .Values.registryName }}\",\"repository\":\"k8s-kubectl\",\"tag\":\"v1.16.10\"},\"iam\":{\"enabled\":true},\"image\":{\"repository\":\"objectscale-operator\"},\"installApplicationCRD\":true,\"installObjectStoreCRD\":true,\"logReceiver\":{\"image\":{\"repository\":\"rsyslog\"},\"persistence\":{\"accessMode\":\"ReadWriteOnce\",\"enabled\":true,\"size\":\"50Gi\"}},\"loggerConfig\":{\"development\":true,\"disableCaller\":false,\"disableStacktrace\":false,\"enabled\":true,\"encoderConfig\":{\"callerEncoder\":\"short\",\"callerKey\":\"C\",\"durationEncoder\":\"string\",\"levelEncoder\":\"capital\",\"levelKey\":\"L\",\"lineEnding\":\"\\n\",\"messageKey\":\"M\",\"nameKey\":\"N\",\"stacktraceKey\":\"S\",\"timeEncoder\":\"iso8601\",\"timeKey\":\"T\"},\"encoding\":\"console\",\"errorOutputPaths\":[\"stderr\"],\"level\":\"info\",\"outputPaths\":[\"stdout\"]},\"nodeSelector\":{},\"objectscale-gateway\":{\"enabled\":false},\"objectscale-iam\":{\"atlas\":{\"disableAntiAffinity\":false,\"image\":{\"pullPolicy\":\"IfNotPresent\",\"repository\":\"atlas\",\"tag\":\"1.1.3\"},\"persistence\":{\"size\":\"10Gi\"},\"replicaCount\":3},\"enabled\":true,\"global\":{\"enableHealthcheck\":false,\"logging_injection_enabled\":true,\"monitoring\":{\"enabled\":true},\"monitoring_registry\":\"{{ .Values.registryName }}\",\"platform\":\"VMware\",\"product\":\"objectscale\",\"registry\":\"{{ .Values.registryName }}\",\"registrySecret\":\"vsphere-docker-secret\",\"rsyslog_enabled\":true,\"storageClassName\":\"dellemc-objectscale-highly-available\",\"watchAllNamespaces\":false},\"image\":{\"pullPolicy\":\"IfNotPresent\",\"repository\":\"iamsvc\"},\"livenessProbe\":{\"probePath\":\"/iamhealthcheck\"},\"readinessProbe\":{\"probePath\":\"/iamhealthcheck/atlas\"},\"replicaCount\":3,\"service\":{\"port\":9400,\"type\":\"LoadBalancer\"},\"tag\":\"0.70.2\"},\"objectscale-monitoring\":{\"influxdb\":{\"persistence\":{\"storageClassName\":\"dellemc-objectscale-highly-available\"}},\"rsyslog\":{\"persistence\":{\"storageClassName\":\"dellemc-objectscale-vsan-sna-thick\"}}},\"pravega\":{\"enabled\":true},\"pravega-operator\":{\"crd\":{\"create\":false},\"global\":{\"enableHealthcheck\":false,\"logging_injection_enabled\":true,\"monitoring\":{\"enabled\":true},\"monitoring_registry\":\"{{ .Values.registryName }}\",\"platform\":\"VMware\",\"product\":\"objectscale\",\"registry\":\"{{ .Values.registryName }}\",\"registrySecret\":\"vsphere-docker-secret\",\"rsyslog_enabled\":true,\"storageClassName\":\"dellemc-objectscale-highly-available\",\"watchAllNamespaces\":false},\"hooks\":{\"backoffLimit\":10,\"image\":{\"repository\":\"k8s-kubectl\",\"tag\":\"v1.16.10\"}},\"image\":{\"pullPolicy\":\"IfNotPresent\",\"repository\":\"pravega-operator\",\"tag\":\"0.5.2-211-24bb31d0\"},\"rbac\":{\"create\":true},\"serviceAccount\":{\"create\":true,\"name\":\"pravega-operator\"},\"testmode\":{\"enabled\":true,\"version\":\"0.10.0\"},\"watchNamespace\":\"\",\"webhookCert\":{\"certName\":\"selfsigned-cert\",\"generate\":false,\"secretName\":\"selfsigned-cert-tls\"}},\"pullPolicy\":\"IfNotPresent\",\"replicaCount\":1,\"resources\":{\"fluentbitAgent\":{\"limits\":{\"memory\":\"40Mi\"},\"requests\":{\"memory\":\"20Mi\"}},\"operator\":{\"limits\":{\"ephemeralStorage\":\"1256Mi\",\"memory\":\"500Mi\"},\"requests\":{\"ephemeralStorage\":\"1256Mi\",\"memory\":\"300Mi\"}},\"rsyslog\":{\"limits\":{\"memory\":\"60Mi\"},\"requests\":{\"memory\":\"30Mi\"}}},\"service-pod\":{\"global\":{\"enableHealthcheck\":false,\"logging_injection_enabled\":true,\"monitoring\":{\"enabled\":true},\"monitoring_registry\":\"{{ .Values.registryName }}\",\"platform\":\"VMware\",\"product\":\"objectscale\",\"registry\":\"{{ .Values.registryName }}\",\"registrySecret\":\"vsphere-docker-secret\",\"rsyslog_enabled\":true,\"storageClassName\":\"dellemc-objectscale-highly-available\",\"watchAllNamespaces\":false},\"image\":{\"repository\":\"base-service-tools\"},\"pullPolicy\":\"IfNotPresent\",\"resources\":{\"limits\":{\"ephemeral-storage\":\"20Gi\"},\"requests\":{\"ephemeral-storage\":\"10Gi\",\"memory\":\"2Gi\"}},\"sshCred\":{\"group\":\"adm\",\"password\":\"ChangeMe\",\"user\":\"root\"},\"tag\":\"2.70.2\"},\"servicePod\":{\"enabled\":true},\"tag\":\"0.70.2\",\"tolerations\":[],\"zookeeper\":{\"enabled\":true},\"zookeeper-operator\":{\"global\":{\"enableHealthcheck\":false,\"installCRD\":true,\"logging_injection_enabled\":true,\"monitoring\":{\"enabled\":true},\"monitoring_registry\":\"{{ .Values.registryName }}\",\"platform\":\"VMware\",\"product\":\"objectscale\",\"registry\":\"{{ .Values.registryName }}\",\"registrySecret\":\"vsphere-docker-secret\",\"rsyslog_enabled\":true,\"storageClassName\":\"dellemc-objectscale-highly-available\",\"watchAllNamespaces\":false},\"image\":{\"pullPolicy\":\"IfNotPresent\",\"repository\":\"zookeeper-operator\",\"tag\":\"0.2.9\"},\"replicaCount\":1}}"
    spec:
      assemblyPhase: Pending
      selector:
        matchLabels:
          app.kubernetes.io/name: objectscale-manager
      componentKinds:
        - group: core
          kind: Service
        - group: apps
          kind: Deployment
        - group: core
          kind: Pod
        - group: core
          kind: ReplicaSet
        - group: core
          kind: ConfigMap
        - group: core
          kind: ServiceAccount
        - group: rbac.authorization.k8s.io
          kind: Role
        - group: rbac.authorization.k8s.io
          kind: RoleBinding
        - group: batch
          kind: CronJob
        - group: batch
          kind: Job
        - group: core
          kind: Secret
      descriptor:
        type: objectscale-manager
        description: Cluster-level management of Dell EMC ObjecScale Object Stores
        version: 0.70.2
        keywords:
          - deos
          - objectscale
          - object store
          - flex
          - ecs
          - s3
        info:
          - "Copyright © 2019 Dell Inc. or its subsidiaries. All Rights Reserved."
    ---
    # Source: kahm/templates/kahm-app.yaml
    apiVersion: app.k8s.io/v1beta1
    kind: Application
    metadata:
      name: "kahm"
      namespace: {{ .service.namespace }}
      labels:
        app.kubernetes.io/name: "kahm"
        app.kubernetes.io/version: 2.70.2
        app.kubernetes.io/instance: kahm
        app.kubernetes.io/managed-by: nautilus
        helm.sh/chart: kahm-2.70.2
        release: kahm
      annotations:
        com.dellemc.kahm.subscribed: "true"
        nautilus.dellemc.com/run-level: "12"
        nautilus.dellemc.com/chart-name: kahm
        nautilus.dellemc.com/chart-version: 2.70.2
        nautilus.dellemc.com/chart-values: "{\"affinity\":{},\"createkahmappResource\":false,\"db\":{\"dbType\":\"BadgerDB\",\"eventTTL\":\"2592000\"},\"global\":{\"platform\":\"VMware\",\"registry\":\"{{ .Values.registryName }}\",\"registrySecret\":\"vsphere-docker-secret\",\"watchAllNamespaces\":false},\"image\":{\"repository\":\"kahm\"},\"nodeSelector\":{},\"pullPolicy\":\"IfNotPresent\",\"replicaCount\":1,\"resources\":{\"requests\":{\"memory\":\"2Gi\"}},\"restapi\":{\"password\":\"ChangeMe\",\"realm\":\"kahm-restapi\",\"username\":\"kahm\"},\"storageClassName\":\"dellemc-objectscale-highly-available\",\"tag\":\"2.70.2\",\"testImage\":{\"repository\":\"kahm-testapp\"},\"tolerations\":[]}"
    spec:
      selector:
        matchLabels:
          app.kubernetes.io/name: "kahm"
      componentKinds:
        - group: apps
          kind: StatefulSet
        - group: core
          kind: ConfigMap
        - group: core
          kind: ServiceAccount
        - group: core
          kind: Pod
        - group: apps
          kind: ReplicaSet
        - group: rbac.authorization.k8s.io
          kind: ClusterRole
        - group: rbac.authorization.k8s.io
          kind: ClusterRoleBinding
      assemblyPhase: "Pending"
      descriptor:
        type: "kahm"
        version: 2.70.2
        description: >
          Kubernetes Application Health Management
        keywords:
          - "kahm"
          - "event"
          - "health"
        info:
          - "Copyright (c) 2019-2020 Dell Inc. or its subsidiaries. All Rights Reserved."
    ---
    # Source: decks/templates/decks-app.yaml
    apiVersion: app.k8s.io/v1beta1
    kind: Application
    metadata:
      name: "decks"
      namespace: {{ .service.namespace }}
      labels:
        app.kubernetes.io/name: "decks"
        app.kubernetes.io/version: 2.70.2
        app.kubernetes.io/instance: decks
        app.kubernetes.io/managed-by: nautilus
        helm.sh/chart: decks-2.70.2
        release: decks
      annotations:
        com.dellemc.kahm.subscribed: "true"
        nautilus.dellemc.com/run-level: "15"
        nautilus.dellemc.com/chart-name: decks
        nautilus.dellemc.com/chart-version: 2.70.2
        nautilus.dellemc.com/chart-values: "{\"affinity\":{},\"createdecksappResource\":false,\"decks-support-store\":{\"affinity\":{},\"containerPort\":7443,\"global\":{\"platform\":\"VMware\",\"registry\":\"{{ .Values.registryName }}\",\"registrySecret\":\"vsphere-docker-secret\",\"watchAllNamespaces\":false},\"image\":{\"pullPolicy\":\"IfNotPresent\",\"repository\":\"decks-support-store\",\"version\":\"2.0.0\"},\"nodeSelector\":{},\"persistentVolume\":{\"size\":\"200Gi\",\"storageClassName\":\"dellemc-objectscale-highly-available\"},\"pullPolicy\":\"IfNotPresent\",\"replicaCount\":1,\"resources\":{},\"service\":{\"port\":7443,\"targetPort\":7443,\"type\":\"ClusterIP\"},\"tag\":\"2.70.2\",\"tolerations\":[]},\"global\":{\"platform\":\"VMware\",\"registry\":\"{{ .Values.registryName }}\",\"registrySecret\":\"vsphere-docker-secret\",\"watchAllNamespaces\":false},\"helmTestConfig\":{\"srsGateway\":{\"port\":9443},\"testImage\":{\"repository\":\"decks-testapp\"}},\"image\":{\"repository\":\"decks\"},\"nodeSelector\":{},\"pullPolicy\":\"IfNotPresent\",\"replicaCount\":1,\"resources\":{},\"supportStore\":{\"enabled\":true},\"tag\":\"2.70.2\",\"tolerations\":[]}"
    spec:
      selector:
        matchLabels:
          app.kubernetes.io/name: "decks"
      componentKinds:
        - group: apps
          kind: Deployment
        - group: core
          kind: ConfigMap
        - group: core
          kind: ServiceAccount
        - group: core
          kind: Pod
        - group: apps
          kind: ReplicaSet
        - group: rbac.authorization.k8s.io
          kind: ClusterRole
        - group: rbac.authorization.k8s.io
          kind: ClusterRoleBinding
      assemblyPhase: "Pending"
      descriptor:
        type: "decks"
        version: 2.70.2
        description: >
          Dell EMC Common Kubernetes Services
        keywords:
          - "decks"
          - "srs"
          - "licensing"
        info:
          - "Copyright (c) 2019-2020 Dell Inc. or its subsidiaries. All Rights Reserved."
    ---
    # Source: logging-injector/templates/logging-injector-app.yaml
    apiVersion: app.k8s.io/v1beta1
    kind: Application
    metadata:
      name: logging-injector
      namespace: {{ .service.namespace }}
      labels:
        app.kubernetes.io/name: logging-injector
        app.kubernetes.io/version: 0.70.2
        app.kubernetes.io/instance: logging-injector
        app.kubernetes.io/managed-by: nautilus
        helm.sh/chart: logging-injector-0.70.2
        release: logging-injector
        product: objectscale
      annotations:
        nautilus.dellemc.com/run-level: "9"    # start before objectscale-manager
        nautilus.dellemc.com/chart-name: logging-injector
        nautilus.dellemc.com/chart-version: 0.70.2
        nautilus.dellemc.com/chart-values: "{\"createApplicationResource\":false,\"global\":{\"objectscale_release_name\":\"objectscale-manager\",\"registry\":\"{{ .Values.registryName }}\",\"registrySecret\":\"vsphere-docker-secret\",\"watchAllNamespaces\":false},\"logging-injector\":{\"common-monitoring-lib\":{\"exports\":{\"default\":{\"rsyslog_client_image_pull_policy\":\"IfNotPresent\",\"rsyslog_client_tag\":null}},\"global\":{\"monitoring_tag\":\"3.7.0.0-1164.08aefd2c\",\"objectscale_release_name\":\"objectscale-manager\",\"registry\":\"{{ .Values.registryName }}\",\"registrySecret\":\"vsphere-docker-secret\",\"rsyslog_client_stdout_enabled\":false,\"rsyslog_enabled\":false,\"watchAllNamespaces\":false}},\"config\":{\"logVolumeName\":\"log\"},\"global\":{\"monitoring_tag\":\"3.7.0.0-1164.08aefd2c\",\"objectscale_release_name\":\"objectscale-manager\",\"registry\":\"{{ .Values.registryName }}\",\"registrySecret\":\"vsphere-docker-secret\",\"rsyslog_client_stdout_enabled\":false,\"rsyslog_enabled\":false,\"watchAllNamespaces\":false},\"image\":{\"pullPolicy\":\"IfNotPresent\",\"repository\":\"logging-injector\"},\"replicas\":1,\"resources\":{\"limits\":{\"memory\":\"256Mi\"},\"requests\":{\"memory\":\"256Mi\"}},\"rsyslog-client\":{\"common-monitoring-lib\":{\"exports\":{\"default\":{\"rsyslog_client_image_pull_policy\":\"IfNotPresent\"}},\"global\":{\"monitoring_tag\":\"3.7.0.0-1164.08aefd2c\",\"objectscale_release_name\":\"objectscale-manager\",\"registry\":\"{{ .Values.registryName }}\",\"registrySecret\":\"vsphere-docker-secret\",\"rsyslog_client_stdout_enabled\":false,\"rsyslog_enabled\":false,\"watchAllNamespaces\":false}},\"config\":{\"logs_size_high_watermark\":\"_204800\",\"logs_size_low_watermark\":\"_153600\",\"maxage\":30,\"output\":{\"port\":10514,\"queue\":{\"size\":10000,\"type\":\"linkedList\"},\"resumeRetryCount\":100}},\"createLogrotateConfigs\":true,\"createRBAC\":true,\"global\":{\"monitoring_tag\":\"3.7.0.0-1164.08aefd2c\",\"objectscale_release_name\":\"objectscale-manager\",\"registry\":\"{{ .Values.registryName }}\",\"registrySecret\":\"vsphere-docker-secret\",\"rsyslog_client_stdout_enabled\":false,\"rsyslog_enabled\":false,\"watchAllNamespaces\":false}},\"tolerations\":[]}}"
    spec:
      assemblyPhase: Pending
      selector:
        matchLabels:
          app.kubernetes.io/name: logging-injector
      componentKinds:
        - group: core
          kind: Service
        - group: apps
          kind: Deployment
        - group: core
          kind: Pod
        - group: core
          kind: ReplicaSet
        - group: core
          kind: ConfigMap
        - group: core
          kind: ServiceAccount
        - group: rbac.authorization.k8s.io
          kind: Role
        - group: rbac.authorization.k8s.io
          kind: RoleBinding
      descriptor:
        type: logging-injector
        description: Logging sidecar injector
        version: 0.70.2
        keywords:
          - objectscale
          - object store
          - flex
          - ecs
          - s3
        info:
          - "Copyright © 2020 Dell Inc. or its subsidiaries. All Rights Reserved."
  objectscale.yaml: |-
    apiVersion: appplatform.wcp.vmware.com/v1alpha1
    kind: SupervisorService
    metadata:
      labels:
        controller-tools.k8s.io: "1.0"
      name: objectscale
      namespace: "kube-system"
    spec:
      serviceId: dellemc-objectscale
      label: Dell EMC ObjectScale
      description: |
        Dell EMC ObjectScale is a dynamically scalable, secure, and multi-tenant object storage platform
        for on-premises and cloud use cases.  It supports advanced storage functionality including
        comprehensive S3 support, flexible erasure-coding, data-at-rest encryption, compression,
        and scales capacity and performance linearly.
      versions: ["0.70.2"]
      enableHostLocalStorage: true
      enabled: false
      eula: |+

        Congratulations on your new Dell EMC purchase!

        Your purchase and use of this Dell EMC product is subject to and governed by the Dell EMC Commercial Terms of Sale, unless you have a separate written agreement with Dell EMC that specifically applies to your order, and the End User License Agreement (E-EULA), which are each presented below in the following order:
        •	Commercial Terms of Sale
        •	End User License Agreement (E-EULA)

        The Commercial Terms of Sale for the United States are presented below and are also available online at the website below that corresponds to the country in which this product was purchased.
        By the act of clicking “I accept,” you agree (or re-affirm your agreement to) the foregoing terms and conditions.  To the extent that Dell Inc. or any Dell Inc.’s direct or indirect subsidiary (“Dell”) is deemed under applicable law to have accepted an offer by you: (a) Dell hereby objects to and rejects all additional or inconsistent terms that may be contained in any purchase order or other documentation submitted by you in connection with your order; and (b) Dell hereby conditions its acceptance on your assent that the foregoing terms and conditions shall exclusively control.
        IF YOU DO NOT AGREE WITH THESE TERMS, DO NOT USE THIS PRODUCT AND CONTACT YOUR DELL REPRESENTATIVE WITHIN FIVE BUSINESS DAYS TO ARRANGE A RETURN.

        Commercial Terms of Sale
        (United States)
        These Commercial Terms of Sale (“CTS”) apply to orders for hardware, software, and services by direct commercial and public sector purchasers and to commercial end-users who purchase through a reseller (“Customer”), unless Customer and Suppliers (defined below) have entered into a separate written agreement that applies to Customer’s orders for specific products or services, in which case, the separate written agreement governs Customer’s purchase and use of such specific products or services.
        The term “Suppliers” means, as applicable:
        EMC Corporation (“EMC”)
        176 South Street
        Hopkinton, Massachusetts 01748
        or
        Dell Marketing L.P. (“Dell”)
        One Dell Way
        Round Rock, Texas 78682
        Email for Legal Notices: Dell_Legal_Notices@dell.com
        Customer may buy or license Products, buy Services, or both, from one or both Suppliers under the CTS, or from an Affiliate that provides Customer a quote referencing the CTS. The General Terms below apply to Suppliers and to Affiliates who provide products and services pursuant to the CTS, unless stated otherwise. The Supplier or Affiliate that issues the quote to Customer is solely responsible to Customer to fulfill the obligations under that quote.
        GENERAL TERMS
        1. DEFINITIONS
        A. “Affiliate” means Dell Inc. or Dell Inc.’s direct or indirect subsidiaries.
        B. “Delivery” for Equipment occurs when Supplier provides the Equipment to a carrier at Supplier’s designated point of shipment. “Delivery” for Software and Independent Software occurs either when Supplier provides physical media to a Supplier-designated carrier at Supplier’s designated point of shipment, or the date Supplier notifies Customer that Software or Independent Software is available for electronic download.
        C. “Documentation” means Supplier’s then current, generally available user manuals and online help for Products.
        D. “Products” means collectively: (i) “Equipment” (which is the hardware that Supplier provides to Customer under the CTS); and (ii) “Software” (which is Suppliers’ generally available application, microcode, firmware and operating system software that Supplier licenses to Customer under the CTS); and (iii) Independent Software (which is Supplier’s software that can operate on hardware other than Equipment). Terms applicable to specific Products are further discussed in the Product Schedules in Section 9 below. Products exclude Services and Third Party Products.
        E. “Providers” means entities (other than Customer) whose components, subassemblies, software, services, or some combination of these items have been incorporated into Products, Services, or both.
        F. “Service Agreements” means service contracts, including service descriptions available at www.dell.com/servicecontracts/global, service briefs, statements of work, services specifications, and any other similar mutually agreed documents.
        G. “Services” means collectively: (i) services for the support and maintenance of Products (“Support Services”) as set forth in Service Schedule referenced in Section 9 below, and applicable Product Schedules; and (ii) consulting, installation, implementation, and other services that are not Support Services (“Professional Services”) further discussed in the Service Schedule referenced in Section 9 below.
        H. “Software Release” means any subsequent, generally available version of Software or Independent Software provided after initial Delivery of Software or Independent Software, but does not mean a new Product.
        I. “Third Party Products” means hardware, software, or services that are not “Dell” branded, “EMC” branded, or “Dell EMC” branded. Third Party Products may include, without limitation, products and services manufactured, created, licensed, or performed by or on behalf of Supplier or its Affiliates, and may include hardware or software installed on a Product in the course of performing a Service.
        2. BUYING PRODUCTS AND SERVICES
        A. Quotes and Orders. “Order” means Customer’s order of Products or Services, through either Dell.com or other online process; and also means Customer purchase orders that reference a Supplier quote and, if applicable, contract code, and Supplier order forms executed by Customer. Orders are subject to credit approval and are subject to Supplier acceptance. Acceptance of one Order is independent from any other Order. Quoted prices are effective until the expiration date of the Supplier’s quote, but may change due to shortages in materials or resources, increase in the cost of manufacturing, or other factors. Orders may contain charges for shipping and handling. Supplier is not responsible for pricing, typographical, or other errors in any offer and may cancel Orders affected by such errors.
        B. Changed or Discontinued Products or Services. Supplier may revise or discontinue products, services, and Third Party Products at any time, including after Customer places an Order, but prior to Supplier’s shipment or performance. As a result, products and services Customer receives may differ from those ordered. However, Dell branded, EMC branded, and Dell EMC branded Products will materially meet or exceed all published specifications for the Products. Parts used in repairing or servicing Products may be new, equivalent-to-new, or reconditioned.
        C. Cancelation and Acceptance. Customer may not cancel Orders except as provided in this sub-section 2.C. Orders for Third-Party Products are subject to availability and are cancellable only by Supplier. All Equipment, Software and Independent Software are deemed accepted by Customer upon Delivery. Customer may return certain Products to Suppliers pursuant to the policy at Dell.com/returnspolicy. Even though Customer accepts Products as stated in the prior sentence, Customer retains all rights and remedies set forth in the applicable Product warranty.
        D. Risk of Loss; Title. Risk of loss for sold Equipment and licensed Software and Independent Software transfers to Customer upon Delivery. Title to Equipment passes to Customer upon Delivery. Title to Software and Independent Software does not pass to Customer. Software and Independent Software are only licensed to Customer and not sold. Unless otherwise agreed, Supplier will choose the common carrier. Customer must notify Dell within thirty days of the invoice date if Customer believes any part of its Order is missing, wrong, or damaged. Dell is not liable for any damage or loss to the product when non-Dell provided shipping method is used for shipping from Dell to the customer. Customer must work with their designated carrier for re-imbursement. Customer is responsible for inspecting the package(s) upon delivery and must note any visible damage on the proof of delivery (POD) or other delivery receipt you may be requested to sign. Dell will not be responsible for any visible shipping damages not noted on the delivery receipt.
        E. Payment. Customer must pay Supplier’s invoices in full and in the same currency as Supplier’s quote within the time noted on Supplier’s invoice, or if not noted, then within thirty days after the date of the invoice, with interest accruing after the due date at the lesser of 1.5% per month or the highest lawful rate. Supplier may invoice parts of an Order separately or together in one invoice. All invoices will be deemed accurate unless Customer advises Supplier in writing of a material error within ten days following receipt. If Customer advises Supplier of a material error, (i) any amounts corrected by Supplier in writing must be paid within fourteen days of correction, and (ii) all other amounts shall be paid by Customer by the due date. If Customer withholds payment because Customer believes an invoiced amount is incorrect, and Supplier concludes that the amount is accurate, Customer must pay interest as described below from the due date for the amount until Supplier’s receipt of payment. Customer may not offset, defer or deduct any invoiced amounts that Supplier determines are correct following the notification process stated above. Supplier, without waiving any other rights or remedies and without liability to Customer, may suspend any or all Services until all overdue amounts are paid in full.
        F. Taxes. Customer is responsible for payment of any sales, use, value added, GST, and any other similar taxes or governmental fees associated with Customer’s Order, except for taxes based on Supplier’s net income, gross revenue, or employment obligations. Customer must also pay all freight, insurance, and taxes (including but not limited to import or export duties, sales, use, value add, and excise taxes). If Supplier is obligated by applicable law to collect and remit any taxes or fees, then Supplier will add the appropriate amount to Customer’s invoices as a separate line item. If Customer qualifies for a tax exemption, Customer must provide Supplier with a valid certificate of exemption or other appropriate proof of exemption. If Customer is required by law to make a withholding or deduction from payment, Customer will make payments to Supplier net of the required withholding or deduction, and will provide to Supplier satisfactory evidence (e.g., official withholding tax receipts) that Customer has accounted to the relevant authority for the sum withheld or deducted. If Customer does not provide the information within sixty days of remittance to the applicable tax authority, Supplier will charge Customer for the amount that Customer deducted for the transaction.
        G. Orders Through Channel Partners. If Customer’s purchase is made through a reseller, then the foregoing sections 2A, 2C, 2D, 2E, and 2F do not apply and all credit, invoicing, payment, returns, ordering, and cancelation terms for the purchase will be as agreed between Customer and the reseller.
        H. Third Party Products, EMC Select and Brokerage Products. Customer may purchase Third Party Products through Suppliers. The terms governing Customer’s use of Third Party Products are as follows:
        H (1). The third party manufacturer’s standard end - user terms, including warranty, indemnification, and technical support and maintenance terms and conditions, apply unless Customer has an applicable separate negotiated agreement with the third party manufacturer for the Third Party Product, in which case that negotiated agreement will govern.
        Suppliers have no liability to Customer for any damages that arise out of or relate to Third Party Products. Suppliers provide Third Party Products “AS IS”, make no express warranties, and disclaim all implied warranties, including merchantability, fitness for a particular purpose, title, and non-infringement as well as any warranty arising by statute, operation of law, course of dealing or performance, or usage of trade.
        H (2). Select and Brokerage Products. Suppliers sell certain products and services designated as “Select” or “Brokerage.” Select and Brokerage products and services generally include Third Party Products, but may also include products manufactured by Supplier or its affiliates. Select products and services are designated “SEL” in the Supplier quote and are provided pursuant to the applicable terms identified for each manufacturer of Select products and services at this website: www.EMC.com/partnersalliances/programs/select.jsp Brokerage products and services are designated “Brokerage” or similar descriptor in the Supplier quote and provided pursuant to the applicable terms and conditions accompanying such Brokerage products and services.
        Notwithstanding the above, Supplier will be responsible under the CTS for Select and Brokerage products and services that are: (i) “Dell”, “EMC” or “Dell EMC” branded, or (ii) provided by an affiliate of Supplier and expressly described in a Product or Service Schedule to the CTS.
        Transactions with Customer Affiliates. Customer Affiliates located in the same country as Customer (the “Initial Country”) may request quotes from, and place purchase orders with, Supplier under this CTS for Products to be used or Services to be performed in the Initial Country, provided that such Customer Affiliates agree to be bound by the terms of this ESA, or are otherwise bound by operation of law. Customer Affiliates located in any other country (the “Additional Country”) may request quotes from, and place purchase orders with, the Supplier Affiliate, if any, conducting business in that Additional Country for Products to be used or Services to be performed in that Additional Country, if the two local Affiliates agree to local governing terms. Those governing terms comprise this CTS and other provisions needed to conform to local laws and business customs, and to the capabilities of the Supplier Affiliate. If there is no Supplier Affiliate for the Additional Country, Supplier will advise Customer of any other way to buy Products and Services.
        3. SOFTWARE LICENSE TERMS. Dell branded, EMC branded, and Dell EMC branded Software that Supplier provides pre-installed on or that only operates on Equipment is subject to the end user license agreement that is included in or with the Software (e.g., in the box for the Product or in the Software’s installer). If there is no end user license agreement included in or with the Software, then the Software is subject to the applicable end user license agreement at www.dell.com/eula. Independent Software is subject to the terms stated in Product Schedule 1 (“Infrastructure Product Terms”).
        A. Services Software. “Services Software” is software that Supplier may make available to Customer in connection with Services. Services Software may be hosted by Supplier or installed on Customer’s computers. Customer agrees that it shall (i) only use the Services Software in connection with the Supplier’s Services, (ii) use any Services Software hosted by Supplier in a lawful manner, without interfering with other Supplier customer’s use of the Services Software, and without attempting to disrupt the security or operation of the network or systems used to provide the Services Software; and (iii) not misappropriate, disclose, or otherwise violate Supplier’s or its Providers’ intellectual property rights in the Services Software. It may be necessary for Supplier to perform scheduled or unscheduled repairs or maintenance, or remotely patch or upgrade the Services Software, which may temporarily degrade the quality of the Services or result in a partial or complete outage of the Services Software. CUSTOMER AGREES THAT THE OPERATION AND AVAILABILITY OF THE SYSTEMS USED FOR ACCESSING AND INTERACTING WITH THE SERVICES SOFTWARE, INCLUDING TELEPHONE, COMPUTER NETWORKS, AND THE INTERNET, OR TO TRANSMIT INFORMATION, CAN BE UNPREDICTABLE AND MAY, FROM TIME TO TIME, INTERFERE WITH OR PREVENT ACCESS TO OR USE OR OPERATION OF SUCH SERVICES SOFTWARE. SUPPLIER SHALL NOT BE LIABLE FOR ANY SUCH INTERFERENCE WITH OR PREVENTION OF CUSTOMER’S ACCESS TO OR USE OF THE SERVICES SOFTWARE.
        B. Third Party Software License Terms. Software for which Supplier is not the licensor (“Third Party Software”) may come with its own license terms (“Separate License Terms”), such as a: (i) “click-to-accept" agreement included as part of the installation or download process; (ii) "shrink-wrap" agreement included in the Product packaging; or (iii) a notice indicating that by installing or using a Product or the component, the related license terms apply. The Separate License Terms govern Customer’s use of Third Party Software. Suppliers provide Third Party Software “AS IS”, make no express warranties, and disclaim all implied warranties, including merchantability, fitness for a particular purpose, title, and non-infringement as well as any warranty arising by statute, operation of law, course of dealing or performance, or usage of trade.
        4. EQUIPMENT WARRANTY, EXCLUSIONS, AND DISCLAIMERS
        A. Equipment Warranty. The warranties for Equipment are stated in the applicable Product Schedules at Section 9 below.
        B. Equipment Warranty Exclusions. Equipment warranties do not cover problems that arise from: (i) accident or neglect by Customer or any third party; (ii) any third party items or services with which the Equipment is used or other causes beyond Supplier’s control; (iii) installation, operation, or use not in accordance with Supplier’s instructions or applicable Documentation; (iv) use in an environment, in a manner, or for a purpose for which the Equipment was not designed; (v) modification, alteration, or repair by anyone other than Supplier or its authorized representatives; or (vi) causes attributable to normal wear and tear. Supplier has no obligation for Software installed or used beyond the licensed use, for Equipment that Customer moved from the Installation Site without Supplier’s consent when applicable, or Product whose original identification marks have been altered or removed or for any Software for which payment has not been received. The Products and Services are not fault-tolerant and are not designed or intended for use in hazardous environments requiring fail-safe performance, such as any application in which the failure of the Products or Services could lead directly to death, personal injury, or physical or property damage (collectively, “High-Risk Activities”). Suppliers expressly disclaim any express or implied warranty of fitness for High-Risk Activities.
        C. Equipment Warranty Disclaimer. Other than the warranties set forth in this Section 4 and the Product and Service Schedules in Section 9, and to the maximum extent permitted by applicable law, Suppliers and Affiliates, and their Providers: (i) make no other express warranties; (ii) disclaim all implied warranties, including merchantability, fitness for a particular purpose, title, and non-infringement; and (iii) disclaim any warranty arising by statute, operation of law, course of dealing or performance, or usage of trade.
        5. TERM; TERMINATION OR SUSPENSION. This CTS is effective upon the earlier of Customer’s issuance of an Order to Supplier, or Customer’s acceptance of the CTS. The CTS continues until it is terminated in accordance with this Section. The term and termination provisions for Support Services are contained in the applicable Product and Services Schedules.
        A. Suspension or Modification of Services.
        Supplier may suspend, terminate, withdraw, or discontinue all or part of the Services when Supplier believes, in its sole judgment, that Customer is involved in any fraudulent or illegal activities.
        B. Termination. Either party may terminate the CTS, a Service Agreement, or license for Software or Independent Software: (i) for a material breach by the other party that is not cured within thirty days of the breaching party’s receipt of written notice of the breach; or (ii) if a party declares bankruptcy or is adjudicated bankrupt or a receiver or trustee is appointed for substantially all of its assets. In addition, Supplier may terminate the CTS or one or more Service Agreements or software licenses with ten days’ written notice if: (a) Customer does not make payment as required by the CTS or the applicable Schedule (where the payment is not subject to a good faith dispute); (b) Customer fails to make the payment within ten days after receiving written notice of the past due amount; (c) Customer purchased through a reseller and, as applicable, (c)(1) the agreement between Customer and the reseller expires or is terminated; (c)(2) the agreement between Supplier and the reseller expires or is terminated; or (c)(3) the reseller is delinquent on its payment obligations to Supplier. Supplier may terminate the CTS and some or all of the Schedules immediately if Customer is acquired by or merged with a competitor of Supplier or any of its Affiliates. Termination of a Service Agreement will not terminate other Service Agreements, and termination of all Service Agreements will not terminate this CTS.
        C. Survival. The provisions relating to payment of outstanding fees, records and audit, confidentiality, and liability will survive termination, all rights of action accruing prior to termination, along with any other provision of the CTS that, expressly, or by its nature and context, is intended to survive
        6. INDEMNITY
        A. Indemnification by Customer. Customer will defend and indemnify Suppliers and Affiliates against any third party claim resulting or arising from Customer’s: (i) failure to obtain any appropriate license, intellectual property rights, or other permissions, regulatory certifications, or approvals associated with technology or data that Customer provides to Suppliers or Affiliates, or with non-Supplier software or other components that Customer directs or requests that Suppliers or Affiliates use with, install, or integrate as part of the Products or Services; (ii) violation of Suppliers’ or Affiliates’ proprietary rights; (iii) misrepresentation of facts regarding an export license or any allegation made against any Supplier or Affiliates due to Customer’s violation or alleged violation of applicable export laws; or (iv) transfer or provision of access to Excluded Data to any Supplier or Affiliates.
        B. Excluded Data. “Excluded Data” means: (i) data that is classified, used on the U.S. Munitions list (including software and technical data) or both; (ii) articles, services, and related technical data designated as defense articles and defense services; and (iii) ITAR (International Traffic in Arms Regulations) related data; and (iv) other personally identifiable information that is subject to heightened security requirements as a result of Customer’s internal policies or practices or by law. Customer acknowledges that products and services provided under the CTS are not designed to process, store, or be used in connection with Excluded Data. Customer is solely responsible for reviewing data that will be provided to or accessed by Suppliers to ensure that it does not contain Excluded Data.
        7. LIMITATION OF LIABILITY
        A. Limitations on Damages. The limitations, exclusions and disclaimers stated below apply to all Disputes (as defined in Section 9F (“Governing Law; Informal Dispute Resolution; Attorney’s Fees”). The terms of this Section are agreed allocations of risk constituting part of the consideration for Suppliers’ and Affiliates’ sale of products and services to Customer and will apply even if there is a failure of the essential purpose of any limited remedy, and regardless whether a party has been advised of the possibility of the liabilities.
        A. (1). Limitation on Direct Damages. Except for Customer’s obligations to pay for products and services, Customer’s violation of the restrictions on use of products and services or Supplier’s intellectual property rights, Customer’s indemnity obligation stated in Section 6 (“Indemnity”), each party’s total liability for Disputes is limited to the amount Customer paid to Supplier during the twelve months before the date that the Dispute arose for the product, services, or both that are the subject of the Dispute, but excluding amounts received as reimbursement of expenses or payment of taxes.
        A. (2). No Indirect Damages. Except for Customer’s payment obligations and violation of Suppliers’ intellectual property rights, neither Supplier nor Customer has liability to the other for special, consequential, exemplary, punitive, incidental, or indirect damages, or for lost profits, loss of revenue, loss of data, or loss of use, or procurement of substitute products or services.
        B. Regular Back-ups. Customer is solely responsible for its data. Customer must back up its data before Supplier performs any remedial, upgrade, or other work on Customer’s production systems. If applicable law prohibits exclusion of liability for lost data, then Supplier will only be liable for the cost of the typical effort to recover the lost data from Customer’s last available back-up.
        C. Limitation Period. Except as stated in this Section 7C, all claims must be made within the period specified by applicable law. If the law allows the parties to specify a shorter period for bringing claims, or the law does not provide a time at all, then claims must be made within eighteen months after the cause of action accrues.
        8. CONFIDENTIALITY. “Confidential Information” is any information, technical data, or know-how furnished, whether in written, oral, electronic, website-based, or other form, by the discloser to the recipient that: (i) is marked, accompanied, or supported by documents clearly and conspicuously designating the documents as "confidential", “internal use”, or the equivalent; (ii) is identified by the discloser as confidential before, during, or promptly after the presentation or communication; or (iii) should reasonably be known by recipient to be confidential. This CTS imposes no obligation upon a recipient with respect to information designated as confidential which: (a) the recipient can demonstrate was already in its possession before receipt from the discloser; (b) is or becomes publicly available through no fault of the recipient or its Representatives (defined below); (c) is rightfully received by the recipient from a third party who has no duty of confidentiality; (d) is disclosed by the discloser to a third party without a duty of confidentiality on the third party; or (e) is independently developed by the recipient without a breach of the CTS. If a recipient is required by a government body or court of law to disclose Confidential Information, to the extent permitted by law, the recipient agrees to give the discloser reasonable advance notice so that the discloser may contest the disclosure or seek a protective order. Recipient will use Confidential Information only for the purpose of and in connection with the evaluation of a potential, or continuation of, a business transaction or relationship between the parties. Recipient may disclose Confidential Information to its directors, officers, employees, and employees of its affiliates, as well as its and its affiliates’ contractors, advisors, and agents, so long as those individuals have a need to know in their work for recipient in furtherance of the potential or continued business transaction or relationship, and are bound by obligations of confidentiality at least as restrictive as those imposed on recipient in this CTS (collectively, “Representatives”). Recipient is fully liable for any breach of this CTS by its Representatives. Recipient will use the same degree of care, but no less than reasonable care, as the recipient uses with respect to its own similar information to protect the Confidential Information. Recipient may only disclose Confidential Information as authorized by this CTS. The terms of this CTS do not restrict the right of recipient to independently design, develop, acquire, market, service, or otherwise deal in, directly or indirectly, products or services competitive with those of the discloser so long as the recipient does not use any of the discloser's Confidential Information for those activities. Unless the parties otherwise agree in writing, a recipient's duty to protect Confidential Information expires three years from the date of disclosure. However, subject to the terms of this Section, the obligation to protect technical information about a discloser’s current products and services and all information about possible unreleased products or services never expires. Upon the discloser's written request, recipient will promptly return or destroy all Confidential Information received from the discloser, together with all copies. Notwithstanding the foregoing, recipient’s professional advisors (e.g., lawyers and accountants) may retain in confidence one file copy of their respective work papers and final reports in accordance with their professional and ethical obligations.
        9. MISCELLANEOUS
        A. References. Supplier may identify Customer as a user of Products, Services, or both, as applicable.
        B. Customer and System Data. In connection with Supplier’s performance or Customer’s use of the Services and Service Software, Supplier may obtain, receive, and/or collect data, including system-specific data (collectively, the “Data”). Customer grants Suppliers: (i) a non-exclusive, worldwide, royalty-free, perpetual, irrevocable license to use, compile, distribute, display, store, process, reproduce, or create derivative works of the Data solely to provide the Services or use the Service Software; (ii) a license to aggregate and use the Data in an anonymous manner in support of Supplier’s marketing and sales activities; and (iii) the right to copy and maintain the Data on Supplier’s or its suppliers’ servers as necessary to provide the Services. Customer represents and warrants that it has obtained all rights, permissions, and consents necessary to use and transfer the Data within and outside of the country in which Customer is located.
        C. Notices. The parties will provide all notices under this CTS in writing. Customer must provide notices to Suppliers, at the Dell email address on the first page of the CTS and, if applicable, Supplier’s address as stated in a Schedule.
        D. Excused Performance. Except for payment of amounts due and owing, neither Supplier nor Customer will be liable for failure to perform its obligations during any period if performance is delayed or rendered impracticable or impossible due to circumstances beyond that party’s reasonable control.
        E. Assignment. Customer may not assign the CTS, a Supplier’s quote, or an Order, or any right or obligation under the CTS, a quote or an Order, or delegate any performance, without Supplier’s prior written consent (except an assignment of Customer’s Order to Dell Financial Services, LLC, does not require consent), which will not be unreasonably withheld. Even if Supplier consents to an assignment or delegation, Customer remains responsible for all obligations to Supplier under the CTS, a quote, or Order that Customer incurred prior to the effective date of the assignment or delegation. Customer attempts to assign or delegate without Supplier’s prior, written consent are void. Supplier may use Affiliates or other qualified subcontractors to provide Services to Customer, but Supplier remains responsible to Customer for the performance of those Services.
        F. Governing Law; Informal Dispute Resolution; Attorney’s Fees. The CTS, and any dispute, claim, or controversy (whether in contract, tort, or otherwise) related to or arising out of the CTS or any quote or Order (“Dispute”) is governed by the laws of the State of Texas (excluding the conflicts of law rules) and the federal laws of the United States. The U.N. Convention on Contracts for the International Sale of Goods does not apply. To the extent permitted by law, the state and federal courts located in Texas will have exclusive jurisdiction for any Disputes. Customer and Suppliers agree to submit to the personal jurisdiction of the state and federal courts located within Travis or Williamson County, Texas, and agree to waive any and all objections to the exercise of jurisdiction over the parties by those courts and to venue in those courts. The parties agree to waive, to the maximum extent permitted by law, any right to a jury trial with respect to any Dispute. Neither Customer nor Suppliers are entitled to join or consolidate claims by or against other customers, or pursue any claim as a representative or class action, or in private attorney general capacity. As a condition precedent to filing any lawsuit, the parties will attempt to resolve any Dispute against one or more Suppliers or any Supplier Affiliate through negotiation with persons fully authorized to resolve the Dispute, or through mediation utilizing a mutually agreeable mediator, rather than through litigation. The existence or results of any negotiation or mediation will be treated as confidential. Although the merits of the underlying Dispute will be resolved in accordance with this Section, any party has the right to obtain from a court of competent jurisdiction a temporary restraining order, preliminary injunction, or other equitable relief to preserve the status quo, prevent irreparable harm, avoid the expiration of any applicable limitation periods, or preserve a superior position with respect to other creditors. If the parties are unable to resolve the Dispute within thirty days (or other mutually agreed time) of notice of the Dispute to the other party, the parties will be free to pursue all remedies available at law or in equity. In any Dispute (other than Supplier’s efforts to collect overdue amounts from Customer) each party will bear its own attorneys’ fees and costs and expressly waives any statutory right to attorneys’ fees under § 38.001 of the Texas Civil Practices and Remedies Code.
        G. Waiver. Failure to enforce a provision of the CTS will not constitute a waiver of that or any other provision of the CTS.
        H. Independent Contractors. The parties are independent contractors for all purposes under the CTS and cannot obligate any other party without prior written approval. The parties do not intend anything in the CTS to allow any party to act as an agent or representative of a party, or the parties to act as joint venturers or partners for any purpose. No party is responsible for the acts or omissions of any other.
        I. Severability. If any part of the CTS or document that incorporates the CTS by reference is held unenforceable, the validity of all remaining parts will not be affected.
        J. Privacy Statements. For information about Supplier’s Privacy Statements, please read Dell's global and country-specific privacy policies at www.Dell.com/Privacy. These policies explain how Dell treats Customer personal information and protects Customer privacy.
        K. Trade Compliance. Customer’s purchase of Products or Services and access to related technology (collectively, the “Materials”) are for its own use, not for resale, export, re-export, or transfer. Customer is subject to and responsible for compliance with the export control and economic sanctions laws of the United States and other applicable jurisdictions. Materials may not be used, sold, leased, exported, imported, re-exported, or transferred except with Supplier’s prior written authorization and in compliance with such laws, including, without limitation, export licensing requirements, end user, end-use, and end-destination restrictions, prohibitions on dealings with sanctioned individuals and entities, including but not limited to persons on the Office of Foreign Assets Control's Specially Designated Nationals and Blocked Persons List, or the U.S. Department of Commerce Denied Persons List. Customer represents and warrants that it is not the subject or target of, and that Customer is not located in a country or territory (including without limitation, North Korea, Cuba, Iran, Syria, and Crimea) that is the subject or target of, economic sanctions of the United States or other applicable jurisdictions.
        L. Encryption. Customer certifies that all items (including hardware, software, technology and other materials) it provides to Dell for any reason that contain or enable encryption functions either (i) satisfy the criteria in the Cryptography Note (Note 3) of Category 5, Part 2 of the Wassenaar Arrangement on Export Controls for Conventional Arms (Wassenaar Arrangement) and Dual-Use Goods and Technologies and Category 5, Part 2 of the U.S. Commerce Control List (CCL) or (ii) employ key length of 56-bit or less symmetric, 512-bit asymmetric or less, and 112-bit or less elliptic curve or (iii) are otherwise not subject to the controls of Category 5, Part 2 of the Wassenaar Arrangement and Category 5, Part 2 of the CCL. Dell is not responsible for determining whether any Third-Party Product to be used in the products and services satisfies regulatory requirements of the country to which such products or services are to be delivered or performed, and Dell shall not be obligated to provide any product or service where the product or service is prohibited by law or does not satisfy the local regulatory requirements
        M. U.S. Government Restricted Rights. The software and documentation provided with the products and services are “commercial items” as that term is defined at 48 C.F.R. 12.101, consisting of “commercial computer software” and “commercial computer software documentation” as such terms are used in 48 C.F.R. 12.212. Consistent with 48 C.F.R. 12.212 and 48 C.F.R. 227.7202-1 through 227.7202-4, all U.S. Government end-users acquire the software and documentation with only those rights set forth herein. Contractor/manufacturer of Dell-branded Software and Dell-branded Products is Dell Products L.P., One Dell Way, Round Rock, Texas 78682.
        N. Entire Agreement; Conflicts. The CTS (including the General Terms and Product and Service Schedules, and other online terms referenced in the CTS), and, if Customer is directly purchasing from Supplier, the Supplier’s quote, and each Order: (i) comprise the complete statement of the agreement of the parties with regard to its subject matter; and (ii) may be modified only in a writing signed by Customer and Supplier. All terms of any Customer Order, including but not limited to (1) any terms that are inconsistent or conflict with this CTS, a Supplier quote, or both, and (2) any pre-printed terms, have no legal effect and do not modify or supplement the CTS, even if Supplier does not expressly object to those terms when accepting a Customer Order. Each Service Agreement will be interpreted independent of any other Service Agreement. If there is a conflict between any Service Agreement and the CTS, the terms of the Service Agreement will take precedence, and in the event of any conflicts between a Product or Service Schedule and the General Terms, the Product or Service Schedule will prevail. In the event that a subject is addressed in both the Supplier Software license agreement provided in or with the Software and the CTS or in any Product or Service Schedule, then the corresponding provision of the Supplier Software license agreement will prevail. No party is relying upon the representations of statements of the other that are not fully expressed in this CTS, and each party expressly disclaims reliance upon any representations or statements not expressly set forth in this CTS. Any claims by any party of fraud in the inducement of this CTS or any Supplier quote or Customer Order based on any statements, representations, understandings, or omissions, whether oral or written, that are not fully expressed in this CTS or the applicable Supplier’s quote are expressly waived and released. Cloud-type services, such as software-as-a-service, storage-as-a-service, and the like, that Customer orders from Supplier are provided pursuant to the Cloud Services Terms of Services located at www.dell.com/dellemccloudterms. The following Product and Service Schedules are incorporated into this CTS.
        Product Schedules:
        www.dell.com/learn/us/en/uscorp1/terms-conditions/cts-product-schedules
        · Product Schedule 1 to CTS – Infrastructure Product Terms
        · Product Schedule 2 to CTS – Networking Product and Server Product Terms
        · Product Schedule 3 to CTS – Client Product Terms
        · Product Schedule 4 to CTS – Pivotal™ Product Terms
        Service Schedules:
        www.dell.com/learn/us/en/uscorp1/terms-conditions/commercialtermsofsale-servicesschedules
        · Service Schedule A to CTS – General Support Services Terms
        · Service Schedule B to CTS – General Professional Services Terms
        · Service Schedule C to CTS – Pivotal Professional Services Terms

        Commercial Terms of Sale (United States)
        Revision Date 11SEP2018

        Commercial Terms of Sale Country Websites

        AMERICAS
        Canada 	Dell.ca/terms
        Canada (French)	Dell.ca/conditions
        Argentina	www.dell.com/learn/ar/es/arcorp1/terms-of-sale

        Aruba	www.dell.com/learn/aw/en/awcorp1/terms-of-sale

        Bahamas	www.dell.com/learn/bs/en/bscorp1/terms-of-sale

        Barbados	http://www1.la.dell.com/content/default.aspx?c=bb&l=en&s=gen&

        Belize	https://www1.la.dell.com/bz/en/gen/df.aspx?refid=df&s=gen&~ck=cr

        Bolivia	www.dell.com/learn/bo/es/bocorp1/terms-of-sale

        Brazil	www.dell.com/br/TermosCondicoe

        Chile	www.dell.com/learn/cl/es/clcorp1/terms-of-sale

        Colombia	www.dell.com/learn/co/es/cocorp1/terms-of-sale

        Costa Rica	www.dell.com/learn/cr/es/crcorp1/terms-conditions/art-site-terms-of-sale-commercial-la?l=es&s=corp

        Ecuador	www.dell.com/learn/ec/es/eccorp1/terms-of-sale

        El Salvador	www.dell.com/learn/sv/es/svcorp1/terms-of-sale

        Guatemala	www.dell.com/learn/gt/es/gtcorp1/terms-of-sale

        Haiti	www.dell.com/learn/ht/en/htcorp1/terms-of-sale

        Honduras	www.dell.com/learn/hn/es/hncorp1/terms-of-sale

        Mexico	www.dell.com/learn/mx/es/mxcorp1/terms-conditions/art-site-commercial-terms-of-sale-mx

        Panama	www.dell.com/learn/pa/es/pacorp1/terms-of-sale

        Paraguay	www.dell.com/learn/py/es/pycorp1/terms-of-sale

        Peru	www.dell.com/learn/pe/es/pecorp1/terms-of-sale

        Uruguay	www.dell.com/learn/uy/es/uycorp1/terms-of-sale

        Venezuela www.dell.com/learn/ve/es/vecorp1/terms-of-sale


        EUROPE
        Austria	www.dell.at/Geschaeftsbedingungen

        Belgium (Dutch)	www.dell.be/voorwaarden

        Belgium (French)	www.dell.be/ConditionsGeneralesdeVente

        Czech	www.dell.cz/podminky

        Denmark	www.dell.dk/salgsbetingelser

        Finland	www.dell.fi/myyntiehdot

        France	www.dell.fr/ConditionsGeneralesdeVente

        Germany	www.dell.de/Geschaeftsbedingungen

        Greece	www.dell.gr/terms

        Ireland	www.dell.ie/terms

        Italy	www.dell.it/condizionigeneralidivendita

        Luxembourg  www.dell.lu/ConditionsGeneralesdeVente

        Netherlands  www.dell.nl/voorwaarden

        Norway	www.dell.no/salgsbetingelser

        Poland	www.dell.pl/warunki

        Portugal	www.dell.pt/ClausulasContratuaisGerais

        Slovakia	www.dell.sk/podmienky

        South Africa  www.dell.co.za/terms

        Spain	www.dell.es/CondicionesGeneralesdeContratacion

        Sweden	www.dell.se/forsaljningsvillkor

        Switzerland (French)  www.dell.ch/termesetconditions

        Switzerland (German)  www.dell.ch/Geschaeftsbedingungen

        UK  www.dell.co.uk/terms


        ASIA and OCEANIA
        Mainland China  www.dell.com/learn/cn/zh/cncorp1/terms-of-sale?s=corp

        Hong Kong  http://www.dell.com/learn/hk/en/hkcorp1/terms-of-sale?s=corp&c=hk&l=en&redirect=1.

        Taiwan	https://www.dell.com/learn/tw/zh/twcorp1/terms-of-sale-commercial-and-public-sector

        Singapore  http://www.dell.com/learn/sg/en/sgcorp1/terms-of-sale-commercial-and-public-sector

        Malaysia	http://www.dell.com/learn/my/en/mycorp1/terms-of-sale-commercial-and-public-sector

        Thailand	http://www.dell.com/learn/th/en/thcorp1/terms-of-sale-commercial-and-public-sector

        Australia	http://www.dell.com/learn/au/en/aucorp1/terms-conditions-of-sale

        New Zealand  http://www.dell.com/learn/nz/en/nzcorp1/terms-of-sale

        India	http://www.dell.com/learn/in/en/incorp1/terms-of-sale-commercial-and-public-sector

        Korea	http://www.dell.com/learn/kr/ko/krcorp1/terms-of-sale-commercial-and-public-sector

        Japan	http://www.dell.com/learn/jp/ja/jpcorp1/terms-of-sale-commercial-and-public-sector (Japan)


        END USER LICENSE AGREEMENT
        For other language versions, go to https://www.dell.com/learn/us/en/uscorp1/campaigns/global-eula
        This Software (meaning application, microcode, firmware, and operating system software in object code format) and associated materials contain proprietary and confidential information, and its use is subject to, and expressly conditioned upon acceptance of, this End User License Agreement and the documents incorporated by reference below (“E-EULA”).
        This E-EULA is a legally binding agreement between the entity that has obtained the Software (“End User”) and Licensor (which may be a Dell Inc. Affiliate or an authorized reseller (“Reseller”), as explained below). If End User has a written, signed agreement with a Dell Inc. Affiliate that expressly provides for the licensing of this Software, then that agreement, and not this E-EULA, will govern.
        End User may have an employee or an employee of a vendor (“You”) download and install the software on End User’s behalf.  This E-EULA becomes binding on End User when You click on the “Agree” or “Accept” or a similar button below, proceed with the installation, download, use, or reproduction of this Software, or otherwise agree to be bound by this E-EULA.  By accepting the E-EULA, as set out in the prior sentence, You represent to Licensor that:
        i.	You have authority to bind the End User to this E-EULA;
        ii.	You agree on behalf of the End User that the terms of this E-EULA govern the relationship of the parties with regard to the subject matter in this E-EULA; and
        iii.	You waive on behalf of End User any rights, to the maximum extent permitted by applicable law, to any claim anywhere in the world concerning the enforceability or validity of this E-EULA.
        If one or more of these representations are not true, then You must do all of the following actions:
        a.	Do not accept the terms of this E-EULA on behalf of the End User by clicking on the “Cancel” or “Decline” or other similar button below;
        b.	Cease any further attempt to install, download, or use this Software and Documentation for any purpose; and
        c.	Remove any partial or full copies made from this Software and Documentation.
        HOW TO DETERMINE THE LICENSOR
        Obtaining Directly from a Dell Inc. Affiliate. If End User procured the Software licenses directly from a Dell Inc. Affiliate, then the “Licensor” under this E-EULA is provided at www.dell.com/swlicensortable. This E-EULA governs End User’s use of the Software.
        Obtaining From a Reseller.  If End User procured the Software licenses from a Reseller, then the Reseller may do one of the following to establish the Licensor and the license terms governing the Software and Documentation:
        Refer to the Manufacturer’s License Terms or Remain Silent on Licensing Terms.  When the Reseller refers End User to a direct license agreement with the software manufacturer, or Reseller says nothing about terms governing the licensing and use of the Software and Documentation, then this E-EULA applies and the applicable Dell Inc. Affiliate identified at www.dell.com/swlicensortable is the “Licensor.”
        Sublicense the Software Rights using the Manufacturer’s Terms.  When the Reseller sublicenses the Software to End User by referring to the software manufacturer’s license terms as the governing terms, then the terms of this E-EULA are deemed incorporated into Reseller’s license agreement with the End User by reference.  If this is case, Reseller is deemed the “Licensor” under this E-EULA.
        1.	DEFINITIONS
        A.	“Affiliate” of End User means a legal entity that is controlled by, controls, or is under common control with End User.  “Control” means more than 50% of the voting power or ownership interests.  “Affiliate” of Dell Inc. means any of Dell Inc.’s direct or indirect subsidiaries.
        B.	“Documentation” means Licensor’s then current, generally available End User manuals and online help for Software.
        C.	“Product Notice” means the information related to Software posted at a Dell Inc. Affiliate website, currently located at http://www.EMC.com/products/warranty_maintenance/index.jsp.  The Product Notice informs End User of Software-specific use rights, restrictions, and definitions of units of measure. The Software-related terms of the Product Notice in effect as of the date of the Quote will apply to the Software and are deemed incorporated into this E-EULA.
        D.	“Quote” means the offer to purchase Software licenses to End User stated in a written quotation or other proposal for providing licenses to Software.  Reseller or a Dell Inc. Affiliate may issue a Quote to End User.
        2.	SOFTWARE LICENSE TERMS
        A.	General License Grant.  Subject to and conditioned on End User’s compliance with the terms of the E-EULA and the Quote, Licensor grants to End User a revocable (according to Section 4 (“Termination”) below), non-exclusive, non-transferable license to use the Software and Documentation during the license term stated on the Quote for End User’s internal business operations. If the Quote does not state a license term, then licenses for Software are perpetual (subject to paragraph B (“Licensing Models”) and Section 4 (“Termination”) below). Use of Software may require End User to complete a product registration process and input a license key.  End User may copy the Software and Documentation as necessary to install and run the Software in the quantity of licensing units licensed, and otherwise only for reasonable back-up and archival purposes.
        B.	Licensing Models.  Licensor licenses Software for use only in accordance with the commercial terms and restrictions of the Software’s relevant software licensing model stated in the Product Notice, the Quote, or both. For example, the licensing model may provide that End User may only use the Software for a certain number of licensing units (e.g., storage capacity, instances, users), in connection with a certain piece of equipment, CPU, network, or other hardware environment, or both. Unless expressly agreed otherwise in writing, Licensor licenses microcode, firmware, and operating system software shipped with equipment for use solely on that equipment; the same applies to Software licensed together with the sale of equipment and designed to enable the equipment to perform enhanced functions.  End User may only use Software licensed at no charge on or with equipment or in the operating environments for which Licensor has designed that Software to operate.
        C.	License Restrictions.  Licensor reserves all rights not expressly granted to End User and does not transfer any ownership rights in any Software. Without Licensor’s prior written consent, End User must not, and must not allow any third party to, do any of the following:
        (1).	use Software in an application services provider, service bureau, or similar capacity;
        (2).	disclose to any third party the results of any comparative or competitive analyses of Software done by or on behalf of End User;
        (3).	make available Software to anyone other than End User’s employees or contractors who will use the Software on behalf of End User in a manner permitted by this E-EULA and the Quote (“Authorized Users”);
        (4).	except to the extent transfer may not legally be restricted under applicable law, transfer or sublicense Software or Documentation to an End User Affiliate or other third party;
        (5).	use Software in conflict with the terms and restrictions specified in this E-EULA or the Quote;
        (6).	except to the extent permitted by applicable mandatory law (meaning laws that parties cannot change by contract), modify, translate, enhance, or create derivative works from the Software, or reverse assemble, disassemble, reverse engineer, decompile, or otherwise attempt to derive source code from the Software;
        (7).	remove any copyright or other proprietary notices on or in any copies of Software or Documentation;
        (8).	violate or circumvent any technological use restrictions in the Software;
        (9).	use the Software or Documentation to create other software, products or technologies; or
        (10).	create Internet “links” to the Software or “frame” or “mirror” the Software.
        D.	Records and Audit.  During the Software license term and for two years after its expiration or termination, End User must maintain accurate records of its use of the Software and Documentation sufficient to show compliance with this E-EULA and the Quotes. During this period, Licensor or its auditors may request that End User certify in writing that End User’s use of the Software and Documentation complies with this E-EULA and the Quotes, audit End User’s use of Software and Documentation to confirm compliance, or both. Licensor will provide End User with reasonable notice and conduct the audit during End User’s normal business hours and will not interfere unreasonably with End User’s business activities when performing the audit.  End User must reasonably cooperate with the audit and must, without prejudice to Licensor’s other rights, promptly buy additional licenses needed to put End User in compliance with the E-EULA and applicable Quotes.  End User must also promptly reimburse Licensor for all reasonable costs of the audit if the audit reveals either that End User used Software in excess of the licenses that End User obtained when the excess usage is more than five percent in license value, or that End User did not maintain substantially accurate Software use records.
        E.	Third Party Software License Terms.  Third party software contained in or with the Software that provides its own terms of use is governed by those provided terms.
        3.	WARRANTIES AND SUPPORT.  Dell Inc. and its Affiliates do not provide any warranties for the Software and do not provide support and maintenance services under this E-EULA.  End User’s rights under any warranties and any support service entitlements for the Software are solely between End User and the entity from whom End User obtained the Software licenses, and are defined under the commercial terms agreed between End User and that selling entity.  If End User obtains support and maintenance from a Reseller in the United States and Canada, then the Dell Inc. Affiliate’s delivery of the maintenance and support services is subject to the applicable terms set forth in the End User License and Support Services Agreement located at the Product Notice website, unless otherwise defined in a separate sublicense, warranty and support, or related services terms agreed between End User and the selling entity.  Subject to the prior sentence, Dell Inc. and its Affiliates and their suppliers provide the Software “As Is” without any warranties or conditions. To the maximum extent permitted by applicable law, Dell Inc. and its Affiliates and their supplier: (i) make no express warranties or conditions; (ii) disclaim all implied warranties and conditions, including merchantability, fitness for a particular purpose, title, and non-infringement; and (iii) disclaim any warranty or condition arising by statute, operation of law, course of dealing or performance, or usage of trade. Where an End User obtains Software at no charge, the End User accepts that such Software is obtained “as is” without any warranty, guarantee, or indemnity of any kind and the Licensor shall be under no obligation to provide any support or maintenance whatsoever.
        4.	TERMINATION.  Licensor may terminate licenses if : (i) End User breaches the license terms and fails to cure within thirty days after receipt of Licensor’s written notice of breach; (ii) End User declares bankruptcy or is adjudicated bankrupt or a receiver or trustee is appointed for substantially all of End User’s assets; or (iii) for Software provided without charge, if there is a critical issue, such as a security vulnerability or third party intellectual property claim.  Dell Inc. or its Affiliates may terminate licenses on ten days’ written notice if End User fails to pay for the Software when payment is not subject to a good faith dispute. Dell Inc. or its Affiliates may terminate the licenses immediately if End User is acquired by or merged with a competitor of Dell Inc. or any of its Affiliates.  If Licensor terminates Software licenses, End User must cease all use of those Software licenses and associated Documentation, and return or certify destruction of Documentation and Software pertaining to the terminated licenses. The provisions of this E-EULA relating to records and audit, confidentiality, and liability will survive termination, along with any other provisions of this E-EULA that, by their nature and context, are intended to survive.
        5.	LIMITATION OF LIABILITY
        A.	Limitations on Damages.  Licensor does not license End User to use Software in situations in which the failure of the Software could lead directly to death, personal injury, or severe physical injury or property damage. Neither party seeks to exclude or limit liability under this E-EULA for death or personal injury resulting from negligence or any other liability that cannot be excluded by law.
        (1).	Limitation on Direct Damages.  Licensor’s total liability to End User is limited to the lower of: (i) the net license fees End User paid for the applicable Software license(s) that gave rise to the liability; or (ii) USD 100,000.
        (2).	No Indirect Damages.  Licensor has no liability for special, consequential, exemplary, punitive, incidental, or indirect damages, or for lost profits, income, revenue, data (including corruption or damage to data), goodwill, reputation, or use of systems, networks, programs, or media.
        B.	Regular Back-ups.  End User is solely responsible for its data.  End User must back up its data before Licensor or a third party performs any remedial, upgrade, or other work on End User’s production systems. If applicable law prohibits exclusion of liability for lost data, then Licensor will only be liable for the cost of the typical effort to recover the lost data from End User’s last available back up.
        C.	Applicability. Even when the Reseller is the Licensor, the limitation of liability stated above will apply in favor of Dell Inc. and its Affiliates, and it will apply to all End User claims, regardless of the course of action (including tort).
        6.	CONFIDENTIALITY. The Software and related materials, including the Documentation, are Dell Inc. and its Affiliates’ “Confidential Information.”  End User must treat the Confidential Information as confidential in perpetuity unless and until the Confidential Information is or becomes part of the public domain through no breach of confidentiality. End User must not use the Confidential Information beyond the scope of the rights granted, and may only share it with Authorized Users who are subject to legal obligations consistent with this E-EULA to protect the confidentiality of the Confidential Information. End User is liable to Dell Inc. and its Affiliates for all use of the Confidential Information by Authorized Users.
        7.	MISCELLANEOUS
        A.	Notices.  The parties will provide all notices under this E-EULA in writing.  Unless provided otherwise in the Quote or on the invoice to End User, End User must provide notices to Dell Inc. and its Affiliates as follows: by mail to: [Licensing Dell Entity Name], Attn: Contracts Manager, One Dell Way, Round Rock, Texas 78682, or by e-mail to: Dell_Legal_Notices@dell.com.  When the Licensor is a Reseller, End User must provide notice to Reseller as stated in the agreement between End User and Reseller or as stated on Reseller’s Quote to End User.
        B.	Assignment.  End User may not assign this E-EULA or a Quote or any right or obligation under this E-EULA or Quote, or delegate any performance, without Licensor’s prior written consent.  Even if Licensor consents to an assignment, End User remains responsible for all obligations to Licensor under this E-EULA and each Quote that End User incurred prior to the effective date of the assignment.  End User attempts to assign or delegate without Licensor’s prior written consent are void.  This section does not prohibit End User from transferring Software and Documentation in accordance with Section 2.C.(4) above.  In case of such transfer, End User must notify Licensor of the transfer in writing and impose all obligations under this E-EULA on the transferee.
        C.	Governing Law and Venue.  This E-EULA and any dispute, claim, or controversy (whether in contract, tort, or otherwise) related to or arising out of this E-EULA or any Quotes (“Dispute”) is governed by the law of the applicable jurisdiction stated in  www.dell.com/swlicensortable (“Governing Jurisdiction”). The U.N. Convention on Contracts for the International Sale of Goods does not apply.  Any Disputes between End User and Dell Inc. or its Affiliates must be brought in the courts of the Governing Jurisdiction.  The parties agree to submit to the personal jurisdiction of the courts within the Governing Jurisdiction in connection with any Disputes.  The parties further waive all objections to the exercise of personal jurisdiction over the parties by those courts, and to venue in those courts, with respect to any such Disputes. The parties agree to waive, to the maximum extent permitted by law, any right to a jury trial with respect to any Dispute.  Neither party is entitled to join or consolidate claims by or against other users, or pursue any claim as a representative or class action, or in private attorney general capacity, in connection with a Dispute.
        D.	Informal Dispute Resolution.  As a condition precedent to filing any lawsuit, a party must first provide written notice of any Dispute to the other party. The parties will attempt to resolve any Dispute through negotiation with persons fully authorized to resolve the Dispute, or through mediation utilizing a mutually agreeable mediator before proceeding with litigation. The parties to a Dispute must treat the existence or results of any negotiation or mediation as confidential.  If the parties are unable to resolve the Dispute within thirty days of notice of the Dispute to the other party (or other mutually agreed period), the parties will be free to pursue all remedies available at law or in equity in accordance with Section 7C above.  Notwithstanding the foregoing, a party may immediately file a lawsuit for injunctive relief to protect intellectual property rights, preserve the status quo, or prevent irreparable harm.
        E.	Waiver.  Failure to enforce a provision of this E-EULA will not constitute a waiver of that or any other provision of this E-EULA.
        F.	Independent Contractors.  The parties are independent contractors for all purposes under this E-EULA and cannot obligate any other party without prior written approval. The parties do not intend anything in this E-EULA to allow any party to act as an agent or representative of a party, or the parties to act as joint venturers or partners for any purpose. No party is responsible for the acts or omissions of any other.
        G.	Severability.  If a court of competent jurisdiction determines any part of this E-EULA or document that incorporates this E-EULA by reference is unenforceable, that ruling will not affect the validity of all remaining parts.
        H.	Trade Compliance.  End User obtains licenses for Software and access to related technology (“Materials”) under this E-EULA for its own use, not for resale, export, re-export, or transfer.  End User is subject to and responsible for compliance with the export control and economic sanctions laws of the United States and other applicable jurisdictions.  Materials may not be used, sold, leased, exported, imported, re-exported, or transferred except with prior written authorization by Dell Inc. or its Affiliates and in compliance with such laws, including, without limitation, export licensing requirements, end-user, end-use, and end-destination restrictions, and prohibitions on dealings with sanctioned individuals and entities, including but not limited to persons on the Office of Foreign Assets Control's Specially Designated Nationals and Blocked Persons List or the U.S. Department of Commerce Denied Persons List.  End User represents and warrants that it is not the subject or target of, and that End User is not located in a country or territory (including without limitation, North Korea, Cuba, Iran, Syria, and Crimea) that is the subject or target of, economic sanctions of the United States or other applicable jurisdictions.  End User understands and will comply with all applicable provisions of the U.S. Arms Export Control Act (AECA) and the U.S. International Traffic in Arms Regulations (ITAR) in End User’s receipt, use, transfer, modification, or disposal of Software.  End User acknowledges that any use, modification, or integration of the Software in or with defense articles or in the provision of defense services is not authorized by any Licensor, and that Licensors will not provide warranty, repair, customer support, or other services in connection with such end uses.  End User certifies that any software, disk images, or other data provided to Licensor in connection with obtaining the Software will not contain technical data, software, or technology controlled by the ITAR or AECA, and that if End User later returns the Software to Licensor or grants Licensor access to the Software, End User will not include or otherwise make available to Licensor any such technical data, software, or technology.  End User agrees to indemnify and hold Licensor harmless for any liability, loss, damage, cost, expense, or penalty arising from End User’s non-compliance with the AECA, ITAR, or the provisions of this Section.
        I.	Obtaining Software from a Reseller; Third Party Beneficiaries.  When a Reseller is the Licensor, End User acknowledges that the sublicense it receives from Reseller is conditional on the license grant from Dell Inc. or its Affiliates to Reseller and that Reseller cannot grant to End User license rights greater than Reseller received from such entity. The applicable Dell Inc. Affiliate is a third party beneficiary to the license agreement between the Reseller and End User and is entitled to exercise and enforce all of Reseller’s rights and benefits under such license agreement (including the terms of this E-EULA).
        J.	Entire Agreement.  This E-EULA comprise the complete statement of the agreement of the parties with regard to its subject matter and may be modified only in a writing signed by both parties. Regardless of the prior sentence, Dell may, in its sole discretion, update the Licensor table and Product Notice incorporated by reference into this E-EULA.  Any changes that Dell Inc. makes to the Licensor table and Product Notice will apply only to transactions that occur after Licensor posts those changes online. The E-EULA excludes all terms of any End User purchase order or similar End User document, such as any preprinted terms, and any terms that supplement, are inconsistent or that conflict with this E-EULA, the Quote, or both.  These excluded terms have no legal effect and do not modify or supplement the E-EULA, even if Licensor does not expressly object to those terms when accepting an End User purchase order or similar document.  Any claims by any party of fraud in the inducement of this E-EULA or any Quote or End User purchase order based on any statements, representations, understandings, or omissions, whether oral or written, that are not fully expressed in this E-EULA, the applicable Quote, or purchase order are expressly waived and released.  End User represents that it did not rely on any representations or statements that do not appear in this E-EULA when accepting this E-EULA.


        INFRASTRUCTURE TELEMETRY NOTICE
        If you are acting on behalf of a U.S. Federal Government agency or if Customer has an express written agreement in place stating that no remote support shall be performed for this machine, please stop attempting to enable the telemetry Collector and contact your sales account representative.

        By continuing to enable this Collector, you acknowledge that you understand the information stated below and accept it.

        Privacy
        Dell, Inc and its group of companies may collect, use and share information, including limited personal information from our customers in connection with the deployment of this telemetry collector (“Collector”). We will collect limited personal data when you register the product or Collector and provide us with your contact details such as name, contact details and the company you work for. For more information on how we use your personal information, including how to exercise your data subject rights, please refer to our Dell Privacy Statement which is available online at https://www.dell.com/learn/us/en/uscorp1/policies-privacy-country-specific-privacy-policy.

        Telemetry Collector
        This Collector gathers system information related to this machine, such as diagnostics, configurations, usage characteristics, performance, and deployment location (collectively, “System Data”), and it manages the remote access and the exchange of the System Data with Dell Inc. or its applicable subsidiaries (together, “Dell”). This Collector is Dell Confidential Information and you may not provide or share it with others. Other than enabling the Collector to run, you do not have a license to use it. By enabling the Collector, Customer consents to Dell’s connection to and remote access of the product containing the Collector and acknowledges that Dell will use the System Data transmitted to Dell via the Collector as follows (“Permitted Purposes”):
        • remotely access the product and Collector to install, maintain, monitor, remotely support, receive alerts and notifications from, and change certain internal system parameters of this product and the Customer’s environment, in fulfillment of applicable warranty and support obligations;
        • provide Customer with visibility to its actual usage and consumption patterns of the product;
        • utilize the System Data in connection with predictive analytics and usage intelligence to consult with and assist Customer, directly or through a reseller, to optimize Customer’s future planning activities and requirements; and
        • “anonymize” (i.e., remove any reference to a specific Customer) and aggregate System Data with that from products of other Customers and use such data to develop and improve products.

        Customer may disable the Collector at any time, in which case all the above activities will stop. Customer acknowledges that this will limit Dell’s ability and obligations (if any) to support the product.

        The Collector does not enable Dell or their service personnel to access, view, process, copy, modify, or handle Customer’s business data stored on or in this product. System Data does not include personally identifiable data relating to any individuals.


        ISG E-EULA
        Revision Date 24MAR2020


EOF

if [ $? -ne 0 ]
then
    echomsg "ERROR unable to apply Dell EMC ObjectScale plugin"
    exit 1
fi 
echo
echomsg "In vSphere7 UI Navigate to Workload-Cluster > Supervisor Services > Services"
echomsg "Select Dell EMC ObjectScale then Enable"