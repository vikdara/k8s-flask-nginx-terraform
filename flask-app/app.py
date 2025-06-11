from flask import Flask, jsonify
from kubernetes import client, config


app = Flask(__name__)


# Try in-cluster config first
try:
    config.load_incluster_config()
except:
    config.load_kube_config()

v1 = client.CoreV1Api()

@app.route("/", methods=["GET"])
def list_pods():
    namespace = "pod-check"
    pods = v1.list_namespaced_pod(namespace=namespace)
    pod_names = [pod.metadata.name for pod in pods.items]

    return jsonify(pod_names)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
