class Api::V1::FormsController < Api::V1::BaseController
  skip_before_action :authenticate_request!, only: %i[index show]
  skip_after_action :verify_authorized, only: %i[index show]
  skip_after_action :verify_policy_scoped, only: %i[index show]

  def index
    schemas = Forms::Interactors::FetchAllFormSchemas.new.call
    render json: Forms::Presenters::FormSchemaPresenter.collection(schemas)
  end

  def show
    schema = Forms::Interactors::FetchFormSchema.new.call(slug: params[:slug])
    render json: Forms::Presenters::FormSchemaPresenter.single(schema)
  rescue Forms::Errors::SchemaNotFound => e
    render json: { errors: [ { status: "404", title: "Not Found", detail: e.message } ] }, status: :not_found
  end

  def create
    authorize :form_schema, :create?, policy_class: Authorization::Policies::FormSchemaPolicy
    schema = Forms::Interactors::CreateFormSchema.new.call(schema_params)
    render json: Forms::Presenters::FormSchemaPresenter.single(schema), status: :created
  rescue Forms::Errors::InvalidSchema => e
    render json: { errors: [ { status: "422", title: "Invalid Schema", detail: e.message } ] }, status: :unprocessable_entity
  end

  def update
    authorize :form_schema, :update?, policy_class: Authorization::Policies::FormSchemaPolicy
    schema = Forms::Interactors::UpdateFormSchema.new.call(params[:slug], schema_params)
    render json: Forms::Presenters::FormSchemaPresenter.single(schema)
  end

  def destroy
    authorize :form_schema, :destroy?, policy_class: Authorization::Policies::FormSchemaPolicy
    Forms::Interactors::DestroyFormSchema.new.call(slug: params[:slug])
    head :no_content
  end

  private

  def schema_params
    params.permit(:slug, :title, :submit_label, :submit_endpoint, :submit_method, :active,
      fields: [ :name, :label, :type, :placeholder, :required, :order, :rows, :default_value,
        { validations: [ :format, :min_length, :max_length, :pattern ] }, { options: [ :label, :value ] } ]).to_h
  end
end
