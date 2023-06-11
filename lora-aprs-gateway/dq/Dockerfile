FROM gcr.io/customer-mol/gce-kube-registry/mojolicious-image

# Your App
ADD app /app

# Carton install
RUN (cd /app && carton install)

# Make it executable
RUN chmod a+rx /app/run.sh
