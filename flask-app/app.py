from flask import Flask, jsonify
from kubernetes import client, config
import traceback

app = Flask(__name__)

try:
    config.load_incluster_config()
except:
    config.load_kube_config()

v1 = client.CoreV1Api()

@app.route("/", methods=["GET"])
def get_pods():
    try:
        pods = v1.list_namespaced_pod(namespace="pod-check")
        pod_names = [pod.metadata.name for pod in pods.items]
        return jsonify(pod_names)
    except Exception as e:
        # Print full stack trace to logs
        traceback.print_exc()
        return {"error": str(e)}, 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
