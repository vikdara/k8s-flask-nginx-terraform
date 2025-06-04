from flask import Flask, jsonify
from kubernetes import client, config

app = Flask(__name__)

@app.route("/pods")
def list_pods():
    config.load_incluster_config()
    v1 = client.CoreV1Api()
    pods = v1.list_namespaced_pod(namespace="default")
    return jsonify([pod.metadata.name for pod in pods.items])

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)