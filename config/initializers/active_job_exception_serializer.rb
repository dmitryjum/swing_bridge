# Allow ActiveJob/Solid Queue to serialize exceptions passed to mailers/jobs.
class ExceptionSerializer < ActiveJob::Serializers::ObjectSerializer
  def serialize?(argument)
    argument.is_a?(Exception)
  end

  def serialize(exception)
    super(
      "class" => exception.class.name,
      "message" => exception.message,
      "backtrace" => Array(exception.backtrace).first(10)
    )
  end

  def deserialize(hash)
    klass = hash["class"].safe_constantize rescue nil
    klass ||= RuntimeError
    error = klass.new(hash["message"])
    error.set_backtrace(hash["backtrace"]) if hash["backtrace"]
    error
  end
end

ActiveJob::Serializers.add_serializers(ExceptionSerializer)
